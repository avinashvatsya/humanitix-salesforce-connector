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
 */
public with sharing class HumanitixSyncQueueable implements Queueable, Database.AllowsCallouts {
    public enum StepOutcome { CONTINUE, RETRY, DONE }

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
                state.attempt, 'Unexpected: ' + e.getMessage()
            );
            HumanitixSyncStateService.recordFailure(
                cursorKey(), phaseToResourceKey(safePhase()), state.currentEventId, state.runId
            );
            advanceWorkItem();
            outcome = state.isDone() ? finalizeAndDone() : StepOutcome.CONTINUE;
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
            String first = HumanitixSyncStateService.nextEventId(null);
            if (String.isBlank(first)) {
                state.advancePhase();
                return state.isDone() ? finalizeAndDone() : StepOutcome.CONTINUE;
            }
            state.currentEventId = first;
            state.page = 1;
        }

        Req req = buildRequest(phase);
        HttpResponse res = null;
        Integer status = null;
        try {
            res = new HumanitixHttpClient(state.namedCredential).get(req.path);
            status = res.getStatusCode();
        } catch (System.CalloutException ce) {
            // Timeout / DNS / connection reset: treat as a retryable no-status
            // outcome rather than letting it hit the fatal catch-all in execute().
            status = null;
        }
        HumanitixRetryPolicy.Outcome oc = HumanitixRetryPolicy.classify(status);

        if (oc == HumanitixRetryPolicy.Outcome.RETRY) {
            state.attempt++;
            if (state.attempt > state.maxRetries) {
                HumanitixSyncLogService.addEntry(
                    state.logId, req.resourceKey, state.currentEventId, 'Failed', 0, 0, state.page, status,
                    state.attempt, 'Max retries exceeded (HTTP ' + status + ')'
                );
                HumanitixSyncStateService.recordFailure(cursorKey(), req.resourceKey, state.currentEventId, state.runId);
                advanceWorkItem();
                return state.isDone() ? finalizeAndDone() : StepOutcome.CONTINUE;
            }
            state.retryDelay = HumanitixRetryPolicy.delayMinutes(
                state.attempt, state.retryDelayMinutes, res == null ? null : res.getHeader('Retry-After')
            );
            return StepOutcome.RETRY;
        }

        if (oc == HumanitixRetryPolicy.Outcome.FATAL) {
            HumanitixSyncLogService.addEntry(
                state.logId, req.resourceKey, state.currentEventId, 'Failed', 0, 0, state.page, status,
                state.attempt, 'HTTP ' + status + ': ' + abbreviate(res == null ? '' : res.getBody())
            );
            HumanitixSyncStateService.recordFailure(cursorKey(), req.resourceKey, state.currentEventId, state.runId);
            advanceWorkItem();
            return state.isDone() ? finalizeAndDone() : StepOutcome.CONTINUE;
        }

        // SUCCESS
        state.attempt = 0;
        HumanitixApiResponse api = HumanitixApiResponse.parse(res.getBody(), req.arrayField, status);
        HumanitixMappingEngine.MappingResult mr = HumanitixMappingEngine.run(req.resourceKey, api.records);
        HumanitixSyncLogService.addEntry(
            state.logId, req.resourceKey, state.currentEventId, mr.hasErrors() ? 'Partial' : 'Success',
            mr.recordsProcessed, mr.recordsFailed, state.page, status, 0,
            mr.errors.isEmpty() ? null : String.join(mr.errors, ' | ')
        );
        // Advance the page from our own state (monotonic), not the server echo, and
        // stop at the ceiling so a metadata-less response can't loop forever.
        if (api.hasNextPage() && state.page < MAX_PAGES_PER_WORK_ITEM) {
            state.page = state.page + 1;
        } else {
            promoteAndAdvance(phase);
        }
        return state.isDone() ? finalizeAndDone() : StepOutcome.CONTINUE;
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
            addSince(q, 'events');
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
            HumanitixSyncStateService.promote('events', 'Event', null, state.runId, state.runStart);
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
        String next = HumanitixSyncStateService.nextEventId(state.currentEventId);
        if (String.isBlank(next)) {
            state.advancePhase();
        } else {
            state.currentEventId = next;
            state.page = 1;
            state.attempt = 0;
        }
    }

    // ---- helpers ----------------------------------------------------------

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

    private static String abbreviate(String body) {
        return String.isBlank(body) ? '' : body.abbreviate(500);
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
