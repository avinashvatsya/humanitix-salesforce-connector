/**
 * The page-chained sync worker. Each execution does exactly ONE callout followed by
 * ONE mapping/DML pass (respecting the "no callout after DML" rule), then chains the
 * next execution carrying a small serializable state. Phases run Tags -> Events ->
 * Orders -> Tickets (only the enabled ones), with Orders/Tickets keyset-iterating
 * over non-archived events.
 *
 * Fault isolation: a fatal/exhausted-retry response on one work item logs a Failed
 * entry and advances to the next work item — one bad event never aborts the run.
 * Incremental: `since` comes from the per-cursor watermark, promoted only on success.
 *
 * A missing or rejected API key ends the run on the first occurrence; an event
 * whose orders or tickets return 404 is archived and skipped (later runs skip it).
 */
public with sharing class HumanitixSyncQueueable implements Queueable, Database.AllowsCallouts {
    public enum StepOutcome { PROCEED, RETRY, DONE }

    // Absolute per-work-item page ceiling — a hard stop against an endpoint that
    // never signals the last page (defense against an unbounded async chain).
    @TestVisible
    private static Integer MAX_PAGES_PER_WORK_ITEM = 10000;

    @TestVisible
    private HumanitixSyncState state;

    public HumanitixSyncQueueable(HumanitixSyncState state) {
        this.state = state;
    }

    public HumanitixSyncState getState() {
        return state;
    }

    public void execute(QueueableContext ctx) {
        StepOutcome outcome;
        try {
            outcome = runStep();
        } catch (Exception e) {
            HumanitixSyncLogService.addEntry(
                state.logId, phaseToResourceKey(safePhase()), state.currentEventId, 'Failed', 0, 0, state.page, null,
                state.attempt, HumanitixSyncMessages.withDetail(HumanitixSyncMessages.unexpected(), e.getMessage())
            );
            HumanitixSyncStateService.recordFailure(
                cursorKey(), phaseToResourceKey(safePhase()), state.currentEventId, state.runId
            );
            advanceWorkItem();
            outcome = state.isDone() ? finalizeAndDone() : StepOutcome.PROCEED;
        }
        chain(outcome);
    }

    @TestVisible
    private StepOutcome runStep() {
        if (!HumanitixSyncConfig.syncEnabled()) {
            return finalizeAndDone();
        }
        String phase = state.currentPhase();
        if (phase == null) {
            return finalizeAndDone();
        }
        if ((phase == 'Orders' || phase == 'Tickets') && String.isBlank(state.currentEventId)) {
            String first = HumanitixSyncStateService.nextEventId(null, eventFilter());
            if (String.isBlank(first)) {
                state.advancePhase();
                return state.isDone() ? finalizeAndDone() : StepOutcome.PROCEED;
            }
            state.currentEventId = first;
            state.page = 1;
        }

        Req req = buildRequest(phase);
        HttpResponse res = null;
        Integer status = null;
        String calloutError = null;
        try {
            res = new HumanitixHttpClient(state.namedCredential).get(req.path);
            status = res.getStatusCode();
        } catch (System.CalloutException ce) {
            calloutError = ce.getMessage();
            if (HumanitixSyncMessages.isMissingCredential(calloutError)) {
                // Every later call would fail the same way: end the run now, no retries.
                return failRun(req.resourceKey, null, HumanitixSyncMessages.withDetail(HumanitixSyncMessages.MISSING_KEY, calloutError));
            }
            // Timeout / DNS / connection reset: treat as a retryable no-status
            // outcome rather than letting it hit the fatal catch-all in execute().
            status = null;
        }
        HumanitixRetryPolicy.Outcome oc = HumanitixRetryPolicy.classify(status);

        if (oc == HumanitixRetryPolicy.Outcome.RETRY) {
            state.attempt++;
            if (state.attempt > state.maxRetries) {
                String msg = status == null
                    ? HumanitixSyncMessages.withDetail(HumanitixSyncMessages.unreachable(state.attempt), calloutError)
                    : HumanitixSyncMessages.withDetail(
                        HumanitixSyncMessages.busy(status, state.attempt), HumanitixSyncMessages.httpDetail(status, res.getBody())
                    );
                HumanitixSyncLogService.addEntry(
                    state.logId, req.resourceKey, state.currentEventId, 'Failed', 0, 0, state.page, status,
                    state.attempt, msg
                );
                HumanitixSyncStateService.recordFailure(cursorKey(), req.resourceKey, state.currentEventId, state.runId);
                advanceWorkItem();
                return state.isDone() ? finalizeAndDone() : StepOutcome.PROCEED;
            }
            state.retryDelay = HumanitixRetryPolicy.delayMinutes(
                state.attempt, state.retryDelayMinutes, res == null ? null : res.getHeader('Retry-After')
            );
            return StepOutcome.RETRY;
        }

        if (oc == HumanitixRetryPolicy.Outcome.FATAL) {
            String detail = HumanitixSyncMessages.httpDetail(status, res.getBody());
            if (status == 401 || status == 403) {
                return failRun(req.resourceKey, status, HumanitixSyncMessages.withDetail(HumanitixSyncMessages.authRejected(status), detail));
            }
            if (status == 404 && (phase == 'Orders' || phase == 'Tickets')) {
                // The event was deleted in Humanitix: archive the staged row so the
                // Orders/Tickets keyset skips it from now on. Not a cursor failure.
                HumanitixSyncLogService.addEntry(
                    state.logId, req.resourceKey, state.currentEventId, 'Skipped', 0, 0, state.page, status,
                    state.attempt, HumanitixSyncMessages.withDetail(HumanitixSyncMessages.eventNotFound(), detail)
                );
                archiveEvent(state.currentEventId);
                moveToNextEventOrPhase();
                return state.isDone() ? finalizeAndDone() : StepOutcome.PROCEED;
            }
            HumanitixSyncLogService.addEntry(
                state.logId, req.resourceKey, state.currentEventId, 'Failed', 0, 0, state.page, status,
                state.attempt, HumanitixSyncMessages.withDetail(HumanitixSyncMessages.refused(status), detail)
            );
            HumanitixSyncStateService.recordFailure(cursorKey(), req.resourceKey, state.currentEventId, state.runId);
            advanceWorkItem();
            return state.isDone() ? finalizeAndDone() : StepOutcome.PROCEED;
        }

        // SUCCESS
        state.attempt = 0;
        HumanitixApiResponse api = HumanitixApiResponse.parse(res.getBody(), req.arrayField, status);
        // Judge "more pages" on the full page, before any selection filter shrinks it.
        Boolean morePages = api.hasNextPage();
        Integer notSelected = (phase == 'Events' && eventFilter() != null) ? keepSelected(api) : 0;
        HumanitixMappingEngine.MappingResult mr = HumanitixMappingEngine.run(req.resourceKey, api.records);
        List<String> notes = new List<String>();
        if (notSelected > 0) {
            notes.add(notSelected + ' event(s) not selected, skipped');
        }
        notes.addAll(mr.errors);
        HumanitixSyncLogService.addEntry(
            state.logId, req.resourceKey, state.currentEventId, mr.hasErrors() ? 'Partial' : 'Success',
            mr.recordsProcessed, mr.recordsFailed, state.page, status, 0,
            notes.isEmpty() ? null : String.join(notes, ' | ')
        );
        // Advance the page from our own state (monotonic), not the server echo, and
        // stop at the ceiling so a metadata-less response can't loop forever.
        if (morePages && state.page < MAX_PAGES_PER_WORK_ITEM) {
            state.page = state.page + 1;
        } else {
            promoteAndAdvance(phase);
        }
        return state.isDone() ? finalizeAndDone() : StepOutcome.PROCEED;
    }

    // ---- request building -------------------------------------------------

    private class Req {
        String path;
        String arrayField;
        String resourceKey;
    }

    private Req buildRequest(String phase) {
        Req r = new Req();
        Map<String, String> q = new Map<String, String>{
            'page' => String.valueOf(state.page),
            'pageSize' => String.valueOf(state.pageSize)
        };
        if (phase == 'Tags') {
            r.path = '/v1/tags';
            r.arrayField = 'tags';
            r.resourceKey = 'Tag';
        } else if (phase == 'Events') {
            r.path = '/v1/events';
            r.arrayField = 'events';
            r.resourceKey = 'Event';
            if (state.inFutureOnly) {
                q.put('inFutureOnly', 'true');
            }
            // In Selected mode the events listing is always fetched in full (it is a
            // few cheap pages), so an event picked after a run is never hidden behind
            // the events cursor. Orders and tickets keep their per-event cursors, and a
            // newly picked event has none, so its orders and tickets are fetched in full.
            if (eventFilter() == null) {
                addSince(q, 'events');
            }
        } else if (phase == 'Orders') {
            r.path = '/v1/events/' + state.currentEventId + '/orders';
            r.arrayField = 'orders';
            r.resourceKey = 'Order';
            addSince(q, 'orders:' + state.currentEventId);
        } else if (phase == 'Tickets') {
            r.path = '/v1/events/' + state.currentEventId + '/tickets';
            r.arrayField = 'tickets';
            r.resourceKey = 'Ticket';
            if (String.isNotBlank(state.ticketStatusFilter)) {
                q.put('status', state.ticketStatusFilter);
            }
            addSince(q, 'tickets:' + state.currentEventId);
        }
        r.path += HumanitixHttpClient.buildQuery(q);
        return r;
    }

    private void addSince(Map<String, String> q, String cursorKey) {
        if (!state.incremental) {
            return;
        }
        Datetime cursor = HumanitixSyncStateService.getCursor(cursorKey);
        if (cursor != null) {
            q.put('since', cursor.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''));
        }
    }

    // ---- advancement ------------------------------------------------------

    private void promoteAndAdvance(String phase) {
        if (phase == 'Events') {
            // Selected mode lists events in full and drops unselected ones, so it must not
            // move the shared cursor: switching back to All would then skip them.
            if (eventFilter() == null) {
                HumanitixSyncStateService.promote('events', 'Event', null, state.runId, state.runStart);
            }
            state.advancePhase();
        } else if (phase == 'Tags') {
            state.advancePhase(); // tags are a full pull; no cursor
        } else if (phase == 'Orders' || phase == 'Tickets') {
            String key = (phase == 'Orders' ? 'orders:' : 'tickets:') + state.currentEventId;
            HumanitixSyncStateService.promote(key, phase == 'Orders' ? 'Order' : 'Ticket', state.currentEventId, state.runId, state.runStart);
            moveToNextEventOrPhase();
        }
    }

    private void advanceWorkItem() {
        String phase = state.currentPhase();
        if (phase == 'Orders' || phase == 'Tickets') {
            moveToNextEventOrPhase();
        } else {
            state.advancePhase();
        }
    }

    private void moveToNextEventOrPhase() {
        String next = HumanitixSyncStateService.nextEventId(state.currentEventId, eventFilter());
        if (String.isBlank(next)) {
            state.advancePhase();
        } else {
            state.currentEventId = next;
            state.page = 1;
            state.attempt = 0;
        }
    }

    /** Logs a run-ending failure (missing or rejected key) and finalizes the run. */
    private StepOutcome failRun(String resourceKey, Integer status, String message) {
        HumanitixSyncLogService.addEntry(
            state.logId, resourceKey, state.currentEventId, 'Failed', 0, 0, state.page, status, state.attempt, message
        );
        HumanitixSyncStateService.recordFailure(cursorKey(), resourceKey, state.currentEventId, state.runId);
        return finalizeAndDone();
    }

    private static void archiveEvent(String humanitixId) {
        List<Humanitix_Event__c> rows = [SELECT Id FROM Humanitix_Event__c WHERE Humanitix_Id__c = :humanitixId LIMIT 1];
        if (!rows.isEmpty()) {
            rows[0].Is_Archived__c = true;
            update rows;
        }
    }

    // ---- helpers ----------------------------------------------------------

    /** The selected event ids in Selected mode; null means "every event". */
    private Set<String> eventFilter() {
        if (state.eventSelection != HumanitixSyncConfig.SELECTION_SELECTED) {
            return null;
        }
        return state.selectedEventIds == null ? new Set<String>() : new Set<String>(state.selectedEventIds);
    }

    /** Drops unselected events from the page in place; returns how many were dropped. */
    private Integer keepSelected(HumanitixApiResponse api) {
        Set<String> wanted = eventFilter();
        List<Object> kept = new List<Object>();
        for (Object o : api.records) {
            if (o instanceof Map<String, Object> && wanted.contains(String.valueOf(((Map<String, Object>) o).get('_id')))) {
                kept.add(o);
            }
        }
        Integer dropped = api.records.size() - kept.size();
        api.records = kept;
        return dropped;
    }

    private String cursorKey() {
        String phase = safePhase();
        if (phase == 'Events') {
            return 'events';
        }
        if (phase == 'Orders') {
            return 'orders:' + state.currentEventId;
        }
        if (phase == 'Tickets') {
            return 'tickets:' + state.currentEventId;
        }
        return 'tags';
    }

    private String safePhase() {
        String p = state.currentPhase();
        return p == null ? 'Unknown' : p;
    }

    private static String phaseToResourceKey(String phase) {
        if (phase == 'Events') {
            return 'Event';
        }
        if (phase == 'Orders') {
            return 'Order';
        }
        if (phase == 'Tickets') {
            return 'Ticket';
        }
        if (phase == 'Tags') {
            return 'Tag';
        }
        return phase;
    }

    private StepOutcome finalizeAndDone() {
        HumanitixSyncLogService.finalizeRun(state.logId);
        state.phaseIndex = state.phases.size(); // ensure isDone()
        return StepOutcome.DONE;
    }

    private void chain(StepOutcome outcome) {
        if (Test.isRunningTest() || outcome == StepOutcome.DONE) {
            return; // tests drive runStep() directly; DONE ends the chain
        }
        if (outcome == StepOutcome.RETRY) {
            Integer delay = (state.retryDelay == null || state.retryDelay < 1) ? 1 : state.retryDelay;
            System.enqueueJob(new HumanitixSyncQueueable(state), delay);
        } else {
            System.enqueueJob(new HumanitixSyncQueueable(state));
        }
    }
}
