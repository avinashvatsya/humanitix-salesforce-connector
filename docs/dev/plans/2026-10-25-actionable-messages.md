# Actionable Messages (1.3.1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace raw platform and HTTP text with one-sentence, actionable messages in the sync log, the launcher and a new Dashboard "Ready to sync" checklist, and release it as package version 1.3.1.

**Architecture:** A pure `HumanitixSyncMessages` class owns every sentence. The queueable uses it to fail fast on a missing key or a rejected key, to skip and archive events that return 404, and to describe exhausted retries; `finalizeRun` rolls the sentences into `Error_Summary__c`, which the Dashboard shows as a Reason column. `HumanitixReadinessService` runs five checks for a new `humanitixReadinessChecklist` LWC on the Dashboard.

**Tech Stack:** Salesforce Apex (API 62.0, `with sharing`), LWC + Jest (`sfdx-lwc-jest`), Python generator scripts, sf CLI v2, 2GP unlocked package.

**Spec:** `docs/dev/specs/2026-10-25-actionable-messages-design.md`.

## Global Constraints

- Dev scratch org alias is **`htx-events`** (exists, no Person Accounts). Dev Hub alias `SAASKOOLProd`.
- Git commits are authored solely by Avinash Vatsya (`avinash.vatsya@saaskool.com`), **with no `Co-Authored-By` or any other Claude trailer.** `git add` explicit paths only.
- **No em dashes (`—`) in any user-facing text**: Apex messages, LWC text, docs.
- CustomMetadata records cannot be deployed (Summer '26 gack); this release changes no records or schema.
- Every new non-test Apex class goes into `ADMIN_APEX_CLASSES` in `scripts/dev/generate-metadata.py` in the same commit, then `python3 scripts/dev/generate-metadata.py` regenerates the permission sets.
- Every Apex test must pass both in an org with seeded mapping records and in a bare org with none.
- Package version: **`1.3.1.NEXT`**, versionName **"Version 1.3.1"**.
- Deploy: `sf project deploy start --target-org htx-events --source-dir force-app --wait 20`. Apex tests: `sf apex run test --target-org htx-events --class-names <Class> --result-format human --wait 20`. Jest: `npx sfdx-lwc-jest`.
- Outward-facing steps (package build/promote, push, PR, Kaipatiki install) need Avinash's go-ahead.

## File Structure

| File | Change | Responsibility |
| --- | --- | --- |
| `classes/HumanitixSyncMessages.cls` (+Test) | Create | Every admin-facing sentence; `Details:` convention |
| `classes/HumanitixSyncQueueable.cls` (+Test) | Modify | Fail fast on missing/rejected key, 404 skip + archive, retry sentences |
| `classes/HumanitixSyncLogService.cls`, `HumanitixSyncLogServiceTest.cls` | Modify / Create | `Error_Summary__c` on finalize |
| `classes/HumanitixSyncLauncher.cls` (+Test) | Modify | Missing key pre-check |
| `classes/HumanitixSyncSettingsController.cls`, `HumanitixConnectionController.cls` | Modify | Delegate the missing-credential rule |
| `classes/HumanitixReadinessService.cls` (+Test) | Create | Five readiness checks |
| `classes/HumanitixSyncAdminController.cls` (+Test) | Modify | `getReadiness()`, `Error_Summary__c` in recent runs |
| `lwc/humanitixReadinessChecklist/**` | Create | Ready to sync card |
| `lwc/humanitixSetupDashboard/**` | Modify | Embed checklist, Reason column |
| `scripts/dev/generate-metadata.py`, `permissionsets/**` | Modify / Generated | New classes in the admin permission set |
| `sfdx-project.json` | Modify | `1.3.1.NEXT` |
| `docs/INSTALL.md`, `docs/CONFIGURATION.md` | Modify | Troubleshooting, checklist, log sentences |

---

### Task 1: Message vocabulary and version bump

**Files:**
- Create: `force-app/main/default/classes/HumanitixSyncMessages.cls`, `HumanitixSyncMessagesTest.cls` (+ `-meta.xml`, API 62.0)
- Modify: `scripts/dev/generate-metadata.py` (`ADMIN_APEX_CLASSES`), `sfdx-project.json`

**Interfaces:**
- Produces: `HumanitixSyncMessages.MISSING_KEY`, `isMissingCredential(String)`, `authRejected(Integer)`, `eventNotFound()`, `busy(Integer, Integer)`, `unreachable(Integer)`, `refused(Integer)`, `unexpected()`, `httpDetail(Integer, String)`, `withDetail(String, String)`, `sentenceOf(String)`.

- [ ] **Step 1: Write the failing test** `HumanitixSyncMessagesTest.cls`:

```apex
@IsTest
private class HumanitixSyncMessagesTest {
    @IsTest
    static void missingCredentialRule() {
        System.assert(HumanitixSyncMessages.isMissingCredential('Field HumanitixAPI.ApiKey does not exist. Check spelling.'));
        System.assert(!HumanitixSyncMessages.isMissingCredential('Read timed out'));
        System.assert(!HumanitixSyncMessages.isMissingCredential(null));
    }

    @IsTest
    static void sentencesNameTheStatusAndAttempts() {
        System.assert(HumanitixSyncMessages.authRejected(401).contains('(HTTP 401)'));
        System.assert(HumanitixSyncMessages.authRejected(403).contains('Connection tab'));
        System.assert(HumanitixSyncMessages.busy(503, 6).contains('(HTTP 503) after 6 attempts'));
        System.assert(HumanitixSyncMessages.unreachable(6).contains('after 6 attempts'));
        System.assert(HumanitixSyncMessages.refused(400).contains('(HTTP 400)'));
        System.assert(HumanitixSyncMessages.eventNotFound().startsWith('This event no longer exists in Humanitix'));
        System.assert(String.isNotBlank(HumanitixSyncMessages.unexpected()));
    }

    @IsTest
    static void detailRoundTrip() {
        String msg = HumanitixSyncMessages.withDetail('Do this.', 'raw text');
        System.assertEquals('Do this. Details: raw text', msg);
        System.assertEquals('Do this.', HumanitixSyncMessages.sentenceOf(msg));
        System.assertEquals('Do this.', HumanitixSyncMessages.withDetail('Do this.', ' '));
        System.assertEquals('Old style text', HumanitixSyncMessages.sentenceOf('Old style text'));
        System.assertEquals(null, HumanitixSyncMessages.sentenceOf(null));
    }

    @IsTest
    static void httpDetailAbbreviatesBody() {
        System.assertEquals('HTTP 404', HumanitixSyncMessages.httpDetail(404, ''));
        System.assertEquals('HTTP 404: {"message":"Not found"}', HumanitixSyncMessages.httpDetail(404, '{"message":"Not found"}'));
        System.assertEquals(510, HumanitixSyncMessages.httpDetail(500, 'x'.repeat(2000)).length());
    }

    @IsTest
    static void noEmDashes() {
        List<String> all = new List<String>{
            HumanitixSyncMessages.MISSING_KEY, HumanitixSyncMessages.authRejected(401), HumanitixSyncMessages.eventNotFound(),
            HumanitixSyncMessages.busy(429, 2), HumanitixSyncMessages.unreachable(2), HumanitixSyncMessages.refused(400),
            HumanitixSyncMessages.unexpected()
        };
        for (String s : all) {
            System.assert(!s.contains('—'), s);
        }
    }
}
```

- [ ] **Step 2: Deploy and run to verify it fails** (compile error: `HumanitixSyncMessages` does not exist).

- [ ] **Step 3: Implement** `HumanitixSyncMessages.cls`:

```apex
/**
 * Every admin-facing sentence the connector shows about a sync problem: sync log
 * entries, the run summary, launch errors and the Dashboard readiness checklist.
 * A log message is "<sentence> Details: <raw>", so the sentence reads first and
 * the raw platform or HTTP text stays available for support.
 */
public with sharing class HumanitixSyncMessages {
    public static final String MISSING_KEY = 'No Humanitix API key is saved. Add it on the Connection tab.';
    public static final String DETAIL_SEPARATOR = ' Details: ';
    private static final Integer MAX_BODY = 500;

    /** The platform says "does not exist" when the external credential has no ApiKey parameter yet. */
    public static Boolean isMissingCredential(String platformMessage) {
        return platformMessage != null && platformMessage.contains('does not exist');
    }

    public static String authRejected(Integer status) {
        return 'Humanitix rejected the API key (HTTP ' + status + '). Check the key on the Connection tab and that '
            + 'the user running the sync has the Humanitix Integration Admin permission set.';
    }

    public static String eventNotFound() {
        return 'This event no longer exists in Humanitix and was skipped. Later runs skip it too.';
    }

    public static String busy(Integer status, Integer attempts) {
        return 'Humanitix was busy or unavailable (HTTP ' + status + ') after ' + attempts
            + ' attempts. The next run tries again.';
    }

    public static String unreachable(Integer attempts) {
        return 'Humanitix could not be reached after ' + attempts + ' attempts. The next run tries again.';
    }

    public static String refused(Integer status) {
        return 'Humanitix refused the request (HTTP ' + status + '). Send this log entry to support if it keeps happening.';
    }

    public static String unexpected() {
        return 'Something unexpected went wrong in this step. Send this log entry to support if it keeps happening.';
    }

    /** "HTTP <status>" plus the response body, abbreviated, when there is one. */
    public static String httpDetail(Integer status, String body) {
        String detail = 'HTTP ' + status;
        return String.isBlank(body) ? detail : detail + ': ' + body.abbreviate(MAX_BODY);
    }

    public static String withDetail(String sentence, String raw) {
        return String.isBlank(raw) ? sentence : sentence + DETAIL_SEPARATOR + raw;
    }

    /** The sentence part of a log message (the whole text for messages written before 1.3.1). */
    public static String sentenceOf(String entryMessage) {
        if (entryMessage == null) {
            return null;
        }
        Integer at = entryMessage.indexOf(DETAIL_SEPARATOR);
        return at < 0 ? entryMessage : entryMessage.left(at);
    }
}
```

- [ ] **Step 4:** Add `"HumanitixSyncMessages",` to `ADMIN_APEX_CLASSES` in `scripts/dev/generate-metadata.py`, run `python3 scripts/dev/generate-metadata.py`. In `sfdx-project.json` set `"versionName": "Version 1.3.1"` and `"versionNumber": "1.3.1.NEXT"`.

- [ ] **Step 5: Deploy, run `HumanitixSyncMessagesTest`**, expect all pass.

- [ ] **Step 6: Commit** `feat: message vocabulary for sync problems; version 1.3.1.NEXT`.

---

### Task 2: Run summary on the log header

**Files:**
- Modify: `force-app/main/default/classes/HumanitixSyncLogService.cls`
- Create: `force-app/main/default/classes/HumanitixSyncLogServiceTest.cls`

**Interfaces:**
- Consumes: `HumanitixSyncMessages.sentenceOf`.
- Produces: `finalizeRun` writes `Error_Summary__c`; `HumanitixSyncLogService.PARTIAL_SENTENCE`.

- [ ] **Step 1: Write the failing test** `HumanitixSyncLogServiceTest.cls`:

```apex
@IsTest
private class HumanitixSyncLogServiceTest {
    private static Humanitix_Sync_Log__c finalized(Id logId) {
        HumanitixSyncLogService.finalizeRun(logId);
        return [SELECT Status__c, Error_Summary__c FROM Humanitix_Sync_Log__c WHERE Id = :logId];
    }

    @IsTest
    static void cleanRunHasNoSummary() {
        Id logId = HumanitixSyncLogService.start('r1', 'Manual', 'Events').Id;
        HumanitixSyncLogService.addEntry(logId, 'Event', null, 'Success', 3, 0, 1, 200, 0, null);
        Humanitix_Sync_Log__c log = finalized(logId);
        System.assertEquals('Success', log.Status__c);
        System.assertEquals(null, log.Error_Summary__c);
    }

    @IsTest
    static void summaryUsesDistinctSentencesWithoutDetails() {
        Id logId = HumanitixSyncLogService.start('r2', 'Manual', 'Orders').Id;
        String busy = HumanitixSyncMessages.busy(503, 6);
        HumanitixSyncLogService.addEntry(logId, 'Order', 'e1', 'Failed', 0, 0, 1, 503, 6, HumanitixSyncMessages.withDetail(busy, 'HTTP 503: a'));
        HumanitixSyncLogService.addEntry(logId, 'Order', 'e2', 'Failed', 0, 0, 1, 503, 6, HumanitixSyncMessages.withDetail(busy, 'HTTP 503: b'));
        HumanitixSyncLogService.addEntry(logId, 'Order', 'e3', 'Partial', 5, 1, 1, 200, 0, 'Row 1: REQUIRED_FIELD_MISSING');
        Humanitix_Sync_Log__c log = finalized(logId);
        System.assertEquals('Partial', log.Status__c);
        System.assertEquals(busy + ' ' + HumanitixSyncLogService.PARTIAL_SENTENCE, log.Error_Summary__c);
    }

    @IsTest
    static void skippedEventsAreCountedAndDoNotDegradeTheRun() {
        Id logId = HumanitixSyncLogService.start('r3', 'Manual', 'Orders,Tickets').Id;
        HumanitixSyncLogService.addEntry(logId, 'Order', 'e1', 'Success', 2, 0, 1, 200, 0, null);
        HumanitixSyncLogService.addEntry(logId, 'Order', 'e2', 'Skipped', 0, 0, 1, 404, 0, HumanitixSyncMessages.eventNotFound());
        HumanitixSyncLogService.addEntry(logId, 'Order', 'e3', 'Skipped', 0, 0, 1, 404, 0, HumanitixSyncMessages.eventNotFound());
        Humanitix_Sync_Log__c log = finalized(logId);
        System.assertEquals('Success', log.Status__c);
        System.assertEquals('2 events no longer exist in Humanitix and were skipped.', log.Error_Summary__c);
    }

    @IsTest
    static void oneSkippedEventIsSingular() {
        Id logId = HumanitixSyncLogService.start('r4', 'Manual', 'Orders').Id;
        HumanitixSyncLogService.addEntry(logId, 'Order', 'e2', 'Skipped', 0, 0, 1, 404, 0, HumanitixSyncMessages.eventNotFound());
        System.assertEquals('1 event no longer exists in Humanitix and was skipped.', finalized(logId).Error_Summary__c);
    }

    @IsTest
    static void blankFailedMessageStillExplains() {
        Id logId = HumanitixSyncLogService.start('r5', 'Manual', 'Tags').Id;
        HumanitixSyncLogService.addEntry(logId, 'Tag', null, 'Failed', 0, 0, 1, null, 0, null);
        Humanitix_Sync_Log__c log = finalized(logId);
        System.assertEquals('Failed', log.Status__c);
        System.assertEquals('A step failed.', log.Error_Summary__c);
    }
}
```

- [ ] **Step 2: Deploy and run**; expect failures (`PARTIAL_SENTENCE` missing).

- [ ] **Step 3: Implement.** In `HumanitixSyncLogService`, add after the class opening brace:

```apex
    public static final String PARTIAL_SENTENCE = 'Some records could not be saved. Open the run\'s log entries for the row errors.';
    private static final Integer MAX_SUMMARY = 1000;
```

add `Error_Summary__c = summarize(logId)` to the `update new Humanitix_Sync_Log__c(...)` in `finalizeRun`, and add:

```apex
    /**
     * Plain-language reason for a degraded run: the distinct sentences of its
     * Failed entries (raw details stripped), one line for row-level errors, and
     * a count of events skipped because Humanitix no longer has them.
     */
    @TestVisible
    private static String summarize(Id logId) {
        List<String> sentences = new List<String>();
        Integer skipped = 0;
        for (Humanitix_Sync_Log_Entry__c e : [
            SELECT Status__c, Error_Message__c
            FROM Humanitix_Sync_Log_Entry__c
            WHERE Humanitix_Sync_Log__c = :logId AND Status__c IN ('Failed', 'Partial', 'Skipped')
            ORDER BY CreatedDate, Id
        ]) {
            if (e.Status__c == 'Skipped') {
                skipped++;
                continue;
            }
            String s = e.Status__c == 'Partial' ? PARTIAL_SENTENCE : HumanitixSyncMessages.sentenceOf(e.Error_Message__c);
            if (String.isBlank(s)) {
                s = 'A step failed.';
            }
            if (!sentences.contains(s)) {
                sentences.add(s);
            }
        }
        if (skipped == 1) {
            sentences.add('1 event no longer exists in Humanitix and was skipped.');
        } else if (skipped > 1) {
            sentences.add(skipped + ' events no longer exist in Humanitix and were skipped.');
        }
        return sentences.isEmpty() ? null : String.join(sentences, ' ').abbreviate(MAX_SUMMARY);
    }
```

- [ ] **Step 4: Deploy, run `HumanitixSyncLogServiceTest`**, expect pass.
- [ ] **Step 5: Commit** `feat: plain-language run summary on the sync log`.

---

### Task 3: Sync engine messages, fail fast and vanished events

**Files:**
- Modify: `force-app/main/default/classes/HumanitixSyncQueueable.cls`, `HumanitixSyncQueueableTest.cls`

**Interfaces:**
- Consumes: Task 1 methods; Task 2 summary (asserted).

- [ ] **Step 1: Write the failing tests** (append to `HumanitixSyncQueueableTest`, next to `ThrowingMock`):

```apex
    private class MissingKeyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new System.CalloutException('Field HumanitixAPI.ApiKey does not exist. Check spelling.');
        }
    }

    @IsTest
    static void missingApiKeyEndsTheRunWithoutRetrying() {
        Test.setMock(HttpCalloutMock.class, new MissingKeyMock());
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Tags', 'Events', 'Orders' }));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = q.runStep();
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.DONE, oc, 'a missing key must not retry');
        Humanitix_Sync_Log_Entry__c entry = [SELECT Status__c, Error_Message__c FROM Humanitix_Sync_Log_Entry__c];
        System.assertEquals('Failed', entry.Status__c);
        System.assert(entry.Error_Message__c.startsWith(HumanitixSyncMessages.MISSING_KEY), entry.Error_Message__c);
        System.assert(entry.Error_Message__c.contains('does not exist'), 'raw detail kept: ' + entry.Error_Message__c);
        Humanitix_Sync_Log__c log = [SELECT Status__c, Error_Summary__c FROM Humanitix_Sync_Log__c WHERE Id = :q.getState().logId];
        System.assertEquals('Failed', log.Status__c);
        System.assertEquals(HumanitixSyncMessages.MISSING_KEY, log.Error_Summary__c);
    }

    @IsTest
    static void rejectedKeyEndsTheRun() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(401, '{"message":"Unauthorized"}'));
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Events', 'Orders', 'Tickets' }));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = q.runStep();
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.DONE, oc, '401 ends the run instead of failing every event');
        Humanitix_Sync_Log_Entry__c entry = [SELECT Status__c, Error_Message__c FROM Humanitix_Sync_Log_Entry__c];
        System.assert(entry.Error_Message__c.startsWith(HumanitixSyncMessages.authRejected(401)), entry.Error_Message__c);
        System.assert(entry.Error_Message__c.contains('Unauthorized'), entry.Error_Message__c);
    }

    @IsTest
    static void vanishedEventIsSkippedArchivedAndRunStaysSuccess() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(404, '{"message":"Event not found"}'));
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Orders', 'Tickets' }));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = q.runStep();
        // Tickets starts its own keyset; the archived event is no longer in it.
        HumanitixSyncQueueable.StepOutcome next = q.runStep();
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.PROCEED, oc);
        System.assertEquals(HumanitixSyncQueueable.StepOutcome.DONE, next, 'the archived event is not iterated again by Tickets');
        Humanitix_Sync_Log_Entry__c entry = [SELECT Status__c, Http_Status__c, Error_Message__c FROM Humanitix_Sync_Log_Entry__c];
        System.assertEquals('Skipped', entry.Status__c);
        System.assert(entry.Error_Message__c.startsWith(HumanitixSyncMessages.eventNotFound()), entry.Error_Message__c);
        System.assert(entry.Error_Message__c.contains('HTTP 404'), entry.Error_Message__c);
        System.assertEquals(true, [SELECT Is_Archived__c FROM Humanitix_Event__c WHERE Humanitix_Id__c = :HumanitixTestDataFactory.EVENT_ID].Is_Archived__c);
        System.assertEquals(0, [SELECT COUNT() FROM Humanitix_Sync_State__c WHERE Last_Status__c = 'Failed'], 'a skipped event is not a cursor failure');
        System.assertEquals('Success', [SELECT Status__c FROM Humanitix_Sync_Log__c WHERE Id = :q.getState().logId].Status__c);
    }

    @IsTest
    static void notFoundOnEventsListIsAFailureNotASkip() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(404, ''));
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Events' }));

        Test.startTest();
        q.runStep();
        Test.stopTest();

        Humanitix_Sync_Log_Entry__c entry = [SELECT Status__c, Error_Message__c FROM Humanitix_Sync_Log_Entry__c];
        System.assertEquals('Failed', entry.Status__c);
        System.assert(entry.Error_Message__c.startsWith(HumanitixSyncMessages.refused(404)), entry.Error_Message__c);
    }

    @IsTest
    static void exhaustedBusyRetriesExplainThemselves() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(503, 'Service Unavailable'));
        HumanitixSyncState st = baseState(new List<String>{ 'Events' });
        st.maxRetries = 1;
        st.attempt = 1;
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(st);

        Test.startTest();
        q.runStep();
        Test.stopTest();

        String msg = [SELECT Error_Message__c FROM Humanitix_Sync_Log_Entry__c].Error_Message__c;
        System.assertEquals(HumanitixSyncMessages.withDetail(HumanitixSyncMessages.busy(503, 2), 'HTTP 503: Service Unavailable'), msg);
    }

    @IsTest
    static void exhaustedTimeoutsExplainThemselves() {
        Test.setMock(HttpCalloutMock.class, new ThrowingMock());
        HumanitixSyncState st = baseState(new List<String>{ 'Events' });
        st.maxRetries = 1;
        st.attempt = 1;
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(st);

        Test.startTest();
        q.runStep();
        Test.stopTest();

        String msg = [SELECT Error_Message__c FROM Humanitix_Sync_Log_Entry__c].Error_Message__c;
        System.assertEquals(HumanitixSyncMessages.withDetail(HumanitixSyncMessages.unreachable(2), 'Read timed out'), msg);
        System.assert(!msg.contains('HTTP null'), msg);
    }
```

`HumanitixSyncStateService.recordFailure` writes `Last_Status__c = 'Failed'`, which is what the vanished-event test asserts is absent.

- [ ] **Step 2: Deploy and run `HumanitixSyncQueueableTest`**; the six new tests fail.

- [ ] **Step 3: Implement** in `HumanitixSyncQueueable.runStep`. Replace the block from `Req req = buildRequest(phase);` to the end of the FATAL branch with:

```apex
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
```

In `execute`, change the catch-all entry text from `'Unexpected: ' + e.getMessage()` to
`HumanitixSyncMessages.withDetail(HumanitixSyncMessages.unexpected(), e.getMessage())`.

Add helpers in the advancement section, and delete the now-unused `abbreviate` helper:

```apex
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
```

Update the class header comment: add "A missing or rejected API key ends the run; an event that returns 404 is archived and skipped."

- [ ] **Step 4: Deploy, run `HumanitixSyncQueueableTest`**, expect all pass (old and new).
- [ ] **Step 5: Commit** `feat: fail fast on a missing or rejected key and skip vanished events`.

---

### Task 4: Launcher pre-check and shared missing-key rule

**Files:**
- Modify: `classes/HumanitixSyncLauncher.cls`, `HumanitixSyncLauncherTest.cls`, `HumanitixSyncSettingsController.cls`, `HumanitixConnectionController.cls`, `HumanitixConnectionControllerTest.cls`

**Interfaces:**
- Consumes: `HumanitixCredentialService.getKeyStatus()` (test seam `HumanitixCredentialService.testStatus`), `HumanitixSyncMessages`.

- [ ] **Step 1: Write the failing tests** (append to `HumanitixSyncLauncherTest`):

```apex
    private static void keyIsMissing() {
        HumanitixCredentialService.KeyStatus st = new HumanitixCredentialService.KeyStatus();
        st.statusKnown = true;
        st.keySaved = false;
        HumanitixCredentialService.testStatus = st;
    }

    @IsTest
    static void missingKeyRefusesToStart() {
        keyIsMissing();
        Test.startTest();
        try {
            HumanitixSyncLauncher.start('Manual');
            System.assert(false, 'expected LaunchException');
        } catch (HumanitixSyncLauncher.LaunchException e) {
            System.assertEquals(HumanitixSyncMessages.MISSING_KEY, e.getMessage());
        }
        Test.stopTest();
        System.assertEquals(null, HumanitixSyncLauncher.lastState, 'nothing is enqueued');
    }

    @IsTest
    static void scheduledRunWithMissingKeyLeavesAFailedRun() {
        keyIsMissing();
        Test.startTest();
        new HumanitixSyncScheduler().execute(null);
        Test.stopTest();
        Humanitix_Sync_Log__c log = [SELECT Status__c, Trigger_Source__c, Error_Summary__c FROM Humanitix_Sync_Log__c];
        System.assertEquals('Failed', log.Status__c);
        System.assertEquals('Scheduled', log.Trigger_Source__c);
        System.assertEquals(HumanitixSyncMessages.MISSING_KEY, log.Error_Summary__c);
    }

    @IsTest
    static void unknownKeyStatusStillStarts() {
        HumanitixCredentialService.KeyStatus st = new HumanitixCredentialService.KeyStatus();
        st.statusKnown = false;
        st.keySaved = false;
        HumanitixCredentialService.testStatus = st;
        Test.startTest();
        Id logId = HumanitixSyncLauncher.start('Manual');
        Test.stopTest();
        System.assertNotEquals(null, logId);
    }
```

And in `HumanitixConnectionControllerTest`:

```apex
    private class MissingKeyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new System.CalloutException('Field HumanitixAPI.ApiKey does not exist. Check spelling.');
        }
    }

    @IsTest
    static void testConnectionExplainsMissingKey() {
        Test.setMock(HttpCalloutMock.class, new MissingKeyMock());
        Test.startTest();
        HumanitixConnectionController.TestResult result = HumanitixConnectionController.testConnection();
        Test.stopTest();
        System.assertEquals(false, result.ok);
        System.assertEquals(HumanitixSyncMessages.MISSING_KEY, result.message);
    }
```

- [ ] **Step 2: Deploy and run both test classes**; the new tests fail.

- [ ] **Step 3: Implement.** In `HumanitixSyncLauncher.start(String, String)`, right after the sync-enabled check:

```apex
        // A known-missing key would only fail on the first callout. Scheduled and
        // Flow callers catch LaunchException, so their Failed run log commits and
        // the reason is visible; a manual run shows the sentence in its toast.
        HumanitixCredentialService.KeyStatus key = HumanitixCredentialService.getKeyStatus();
        if (key != null && key.statusKnown == true && key.keySaved != true) {
            Datetime failedAt = Datetime.now();
            Humanitix_Sync_Log__c failed = HumanitixSyncLogService.start(
                triggerSource + '-' + String.valueOf(failedAt.getTime()) + '-' + String.valueOf(Math.abs(Crypto.getRandomLong())),
                triggerSource,
                String.join(HumanitixSyncConfig.enabledResources(), ',')
            );
            HumanitixSyncLogService.addEntry(failed.Id, null, null, 'Failed', 0, 0, 0, null, 0, HumanitixSyncMessages.MISSING_KEY);
            HumanitixSyncLogService.finalizeRun(failed.Id);
            throw new LaunchException(HumanitixSyncMessages.MISSING_KEY);
        }
```

In `HumanitixSyncSettingsController.calloutFailureMessage`, replace the condition with
`if (HumanitixSyncMessages.isMissingCredential(platformMessage)) {` and drop its now-duplicated doc comment line.

In `HumanitixConnectionController.testConnection`'s catch block:

```apex
            result.message = HumanitixSyncMessages.isMissingCredential(e.getMessage())
                ? HumanitixSyncMessages.MISSING_KEY
                : 'The connection attempt failed: ' + e.getMessage();
```

- [ ] **Step 4: Deploy, run `HumanitixSyncLauncherTest`, `HumanitixConnectionControllerTest`, `HumanitixSyncSettingsControllerTest`, `HumanitixSyncAdminControllerTest`**, expect pass.
- [ ] **Step 5: Commit** `feat: refuse to start a sync when no API key is saved`.

---

### Task 5: Readiness service

**Files:**
- Create: `classes/HumanitixReadinessService.cls`, `HumanitixReadinessServiceTest.cls`
- Modify: `classes/HumanitixSyncAdminController.cls` (+Test), `scripts/dev/generate-metadata.py`

**Interfaces:**
- Produces: `HumanitixReadinessService.Item { key, label, status, message }`, `check()`; `HumanitixSyncAdminController.getReadiness()`; `getRecentRuns()` returns `Error_Summary__c`.

- [ ] **Step 1: Write the failing test** `HumanitixReadinessServiceTest.cls`:

```apex
@IsTest
private class HumanitixReadinessServiceTest {
    private static HumanitixCredentialService.KeyStatus key(Boolean known, Boolean saved) {
        HumanitixCredentialService.KeyStatus st = new HumanitixCredentialService.KeyStatus();
        st.statusKnown = known;
        st.keySaved = saved;
        return st;
    }

    private static User fakeUser(String id, String name, Boolean marketing) {
        return (User) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{ 'Id' => id, 'Name' => name, 'UserPermissionsMarketingUser' => marketing }),
            User.class
        );
    }

    private static Map<String, HumanitixReadinessService.Item> byKey(List<HumanitixReadinessService.Item> items) {
        Map<String, HumanitixReadinessService.Item> m = new Map<String, HumanitixReadinessService.Item>();
        for (HumanitixReadinessService.Item i : items) {
            m.put(i.key, i);
        }
        return m;
    }

    @IsTest
    static void apiKeyItemStates() {
        System.assertEquals('ok', HumanitixReadinessService.apiKeyItem(key(true, true)).status);
        HumanitixReadinessService.Item missing = HumanitixReadinessService.apiKeyItem(key(true, false));
        System.assertEquals('error', missing.status);
        System.assertEquals(HumanitixSyncMessages.MISSING_KEY, missing.message);
        System.assertEquals('unknown', HumanitixReadinessService.apiKeyItem(key(false, false)).status);
    }

    @IsTest
    static void connectionSkippedWithoutKey() {
        HumanitixReadinessService.Item i = HumanitixReadinessService.connectionItem(key(true, false));
        System.assertEquals('unknown', i.status);
        System.assertEquals('Add the API key first.', i.message);
    }

    @IsTest
    static void connectionOkAndRejected() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(200, '{}').enqueue(401, ''));
        Test.startTest();
        HumanitixReadinessService.Item ok = HumanitixReadinessService.connectionItem(key(true, true));
        HumanitixReadinessService.Item rejected = HumanitixReadinessService.connectionItem(key(true, true));
        Test.stopTest();
        System.assertEquals('ok', ok.status);
        System.assertEquals('error', rejected.status);
        System.assertEquals(HumanitixSyncMessages.authRejected(401), rejected.message);
    }

    @IsTest
    static void connectionBusyIsAWarning() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(503, ''));
        Test.startTest();
        HumanitixReadinessService.Item i = HumanitixReadinessService.connectionItem(key(false, false));
        Test.stopTest();
        System.assertEquals('warning', i.status);
    }

    @IsTest
    static void marketingUserNamesTheFailingUsers() {
        User ok = fakeUser('005000000000001', 'Ana Admin', true);
        User bad = fakeUser('005000000000002', 'Sam Scheduler', false);
        System.assertEquals('ok', HumanitixReadinessService.marketingUserItem(new List<User>{ ok }).status);
        HumanitixReadinessService.Item i = HumanitixReadinessService.marketingUserItem(new List<User>{ ok, bad });
        System.assertEquals('error', i.status);
        System.assert(i.message.startsWith('Sam Scheduler is not a Marketing User'), i.message);
        System.assert(!i.message.contains('Ana Admin'), i.message);
    }

    @IsTest
    static void permissionSetNamesTheFailingUsers() {
        User a = fakeUser('005000000000001', 'Ana Admin', true);
        User b = fakeUser('005000000000002', 'Sam Scheduler', true);
        HumanitixReadinessService.Item ok = HumanitixReadinessService.permissionSetItem(new List<User>{ a, b }, new Set<Id>{ a.Id, b.Id });
        System.assertEquals('ok', ok.status);
        System.assert(ok.message.startsWith('Ana Admin, Sam Scheduler have'), ok.message);
        HumanitixReadinessService.Item i = HumanitixReadinessService.permissionSetItem(new List<User>{ a, b }, new Set<Id>{ a.Id });
        System.assertEquals('error', i.status);
        System.assert(i.message.startsWith('Sam Scheduler does not have the Humanitix Integration Admin permission set.'), i.message);
    }

    @IsTest
    static void scheduleWarnsWhenMissingAndPassesWhenSet() {
        HumanitixCredentialService.testStatus = key(true, false); // no callout in this test
        Map<String, HumanitixReadinessService.Item> before = byKey(HumanitixReadinessService.check());
        System.assertEquals('warning', before.get('schedule').status);
        HumanitixSyncScheduler.schedule('Humanitix Delta Sync 1', '0 0 2 * * ?', HumanitixSyncLauncher.MODE_DELTA);
        Map<String, HumanitixReadinessService.Item> after = byKey(HumanitixReadinessService.check());
        System.assertEquals('ok', after.get('schedule').status);
    }

    @IsTest
    static void checkReturnsFiveItemsInOrder() {
        HumanitixCredentialService.testStatus = key(true, false);
        List<HumanitixReadinessService.Item> items = HumanitixReadinessService.check();
        List<String> keys = new List<String>();
        for (HumanitixReadinessService.Item i : items) {
            keys.add(i.key);
            System.assert(String.isNotBlank(i.message), i.key);
            System.assert(!i.message.contains('—'), i.message);
        }
        System.assertEquals(new List<String>{ 'apiKey', 'connection', 'marketingUser', 'permissionSet', 'schedule' }, keys);
    }
}
```

Add to `HumanitixSyncAdminControllerTest`:

```apex
    @IsTest
    static void getReadinessReturnsTheChecklist() {
        Test.startTest();
        List<HumanitixReadinessService.Item> items = HumanitixSyncAdminController.getReadiness();
        Test.stopTest();
        System.assertEquals(5, items.size());
    }
```

- [ ] **Step 2: Deploy**; compile fails (class missing).

- [ ] **Step 3: Implement** `HumanitixReadinessService.cls`:

```apex
/**
 * The Dashboard's "Ready to sync" checklist. Each check says in one sentence
 * what to do and where when it is not ok; a check that cannot run reports
 * unknown instead of hiding the others.
 *
 * Users checked: the current user (manual runs run as them) and the owners of
 * active Humanitix scheduled jobs (scheduled runs run as the user who scheduled
 * them).
 */
public with sharing class HumanitixReadinessService {
    public static final String OK = 'ok';
    public static final String ERROR = 'error';
    public static final String WARNING = 'warning';
    public static final String UNKNOWN = 'unknown';
    @TestVisible
    private static final String ADMIN_PERMISSION_SET = 'Humanitix_Integration_Admin';
    private static final Set<String> ACTIVE_JOB_STATES = new Set<String>{ 'WAITING', 'ACQUIRED', 'EXECUTING' };

    public class Item {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String status;
        @AuraEnabled public String message;

        public Item(String key, String label, String status, String message) {
            this.key = key;
            this.label = label;
            this.status = status;
            this.message = message;
        }
    }

    public static List<Item> check() {
        List<Item> items = new List<Item>();
        HumanitixCredentialService.KeyStatus key = null;
        try {
            key = HumanitixCredentialService.getKeyStatus();
            items.add(apiKeyItem(key));
        } catch (Exception e) {
            items.add(apiKeyItem(null));
        }
        items.add(connectionItem(key));

        Set<Id> jobOwners = null;
        try {
            jobOwners = activeJobOwners();
        } catch (Exception e) {
            jobOwners = null;
        }
        try {
            List<User> users = usersToCheck(jobOwners == null ? new Set<Id>() : jobOwners);
            items.add(marketingUserItem(users));
            items.add(permissionSetItem(users, permissionSetHolders(users)));
        } catch (Exception e) {
            items.add(new Item('marketingUser', 'Marketing User', UNKNOWN, 'The users could not be checked: ' + e.getMessage()));
            items.add(new Item('permissionSet', 'Permission set', UNKNOWN, 'The users could not be checked: ' + e.getMessage()));
        }
        items.add(scheduleItem(jobOwners));
        return items;
    }

    @TestVisible
    private static Item apiKeyItem(HumanitixCredentialService.KeyStatus key) {
        if (key == null || key.statusKnown != true) {
            return new Item(
                'apiKey', 'API key saved', UNKNOWN,
                'The key could not be checked from this page. Use Test Connection on the Connection tab.'
            );
        }
        return key.keySaved == true
            ? new Item('apiKey', 'API key saved', OK, 'An API key is saved.')
            : new Item('apiKey', 'API key saved', ERROR, HumanitixSyncMessages.MISSING_KEY);
    }

    @TestVisible
    private static Item connectionItem(HumanitixCredentialService.KeyStatus key) {
        String label = 'Connection to Humanitix';
        if (key != null && key.statusKnown == true && key.keySaved != true) {
            return new Item('connection', label, UNKNOWN, 'Add the API key first.');
        }
        try {
            HttpResponse res = new HumanitixHttpClient(HumanitixSyncConfig.namedCredentialName())
                .get('/v1/events?page=1&pageSize=1');
            Integer s = res.getStatusCode();
            if (s >= 200 && s < 300) {
                return new Item('connection', label, OK, 'Humanitix accepted the API key.');
            }
            if (s == 401 || s == 403) {
                return new Item('connection', label, ERROR, HumanitixSyncMessages.authRejected(s));
            }
            if (HumanitixRetryPolicy.isRetryable(s)) {
                return new Item('connection', label, WARNING, 'Humanitix is busy or unavailable right now. Refresh in a minute.');
            }
            return new Item(
                'connection', label, ERROR,
                'Humanitix returned HTTP ' + s + '. Use Test Connection on the Connection tab for details.'
            );
        } catch (Exception e) {
            if (HumanitixSyncMessages.isMissingCredential(e.getMessage())) {
                return new Item('connection', label, ERROR, HumanitixSyncMessages.MISSING_KEY);
            }
            return new Item(
                'connection', label, ERROR,
                'Humanitix could not be reached (' + e.getMessage() + '). Use Test Connection on the Connection tab for details.'
            );
        }
    }

    @TestVisible
    private static Item marketingUserItem(List<User> users) {
        List<String> all = new List<String>();
        List<String> failing = new List<String>();
        for (User u : users) {
            all.add(u.Name);
            if (u.UserPermissionsMarketingUser != true) {
                failing.add(u.Name);
            }
        }
        if (failing.isEmpty()) {
            return new Item('marketingUser', 'Marketing User', OK, String.join(all, ', ') + ' can create Campaigns.');
        }
        return new Item(
            'marketingUser', 'Marketing User', ERROR,
            String.join(failing, ', ') + (failing.size() == 1 ? ' is not a Marketing User' : ' are not Marketing Users')
                + ', so Campaigns cannot be created. Tick Marketing User on the user record in Setup, Users.'
        );
    }

    @TestVisible
    private static Item permissionSetItem(List<User> users, Set<Id> holders) {
        List<String> all = new List<String>();
        List<String> failing = new List<String>();
        for (User u : users) {
            all.add(u.Name);
            if (!holders.contains(u.Id)) {
                failing.add(u.Name);
            }
        }
        if (failing.isEmpty()) {
            return new Item(
                'permissionSet', 'Permission set', OK,
                String.join(all, ', ') + (all.size() == 1 ? ' has' : ' have') + ' the Humanitix Integration Admin permission set.'
            );
        }
        return new Item(
            'permissionSet', 'Permission set', ERROR,
            String.join(failing, ', ') + (failing.size() == 1 ? ' does not have' : ' do not have')
                + ' the Humanitix Integration Admin permission set. Assign it in Setup, Permission Sets.'
        );
    }

    @TestVisible
    private static Item scheduleItem(Set<Id> jobOwners) {
        if (jobOwners == null) {
            return new Item('schedule', 'Schedule', UNKNOWN, 'The schedule could not be checked. Open the Schedule tab.');
        }
        return jobOwners.isEmpty()
            ? new Item(
                'schedule', 'Schedule', WARNING,
                'No schedule is set, so syncs run only when you click Run Sync Now. Set one on the Schedule tab.'
            )
            : new Item('schedule', 'Schedule', OK, 'A sync schedule is set.');
    }

    private static Set<Id> activeJobOwners() {
        Set<Id> owners = new Set<Id>();
        for (CronTrigger ct : [
            SELECT OwnerId
            FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'Humanitix%' AND State IN :ACTIVE_JOB_STATES
        ]) {
            owners.add(ct.OwnerId);
        }
        return owners;
    }

    private static List<User> usersToCheck(Set<Id> jobOwners) {
        Set<Id> ids = new Set<Id>(jobOwners);
        ids.add(UserInfo.getUserId());
        return [SELECT Id, Name, UserPermissionsMarketingUser FROM User WHERE Id IN :ids ORDER BY Name];
    }

    private static Set<Id> permissionSetHolders(List<User> users) {
        Set<Id> holders = new Set<Id>();
        for (PermissionSetAssignment a : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSet.Name = :ADMIN_PERMISSION_SET AND AssigneeId IN :users
        ]) {
            holders.add(a.AssigneeId);
        }
        return holders;
    }
}
```

In `HumanitixSyncAdminController` add:

```apex
    /** The Dashboard "Ready to sync" checklist. Not cacheable: it includes a live connection check. */
    @AuraEnabled
    public static List<HumanitixReadinessService.Item> getReadiness() {
        try {
            return HumanitixReadinessService.check();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
```

and add `Error_Summary__c` to the `getRecentRuns` SELECT list.

Add `"HumanitixReadinessService",` to `ADMIN_APEX_CLASSES` and run `python3 scripts/dev/generate-metadata.py`.

- [ ] **Step 4: Deploy, run `HumanitixReadinessServiceTest`, `HumanitixSyncAdminControllerTest`**, expect pass.
- [ ] **Step 5: Commit** `feat: readiness checks for the Dashboard`.

---

### Task 6: Ready to sync checklist and Reason column

**Files:**
- Create: `lwc/humanitixReadinessChecklist/humanitixReadinessChecklist.{html,js,js-meta.xml}`, `__tests__/humanitixReadinessChecklist.test.js`
- Modify: `lwc/humanitixSetupDashboard/humanitixSetupDashboard.{html,js}`, `__tests__/humanitixSetupDashboard.test.js`

**Interfaces:**
- Consumes: `@salesforce/apex/HumanitixSyncAdminController.getReadiness` returning `[{ key, label, status, message }]`; `errorMessage` from `c/humanitixSetupUtils`.

- [ ] **Step 1: Write the failing Jest test** `humanitixReadinessChecklist.test.js`:

```js
import { createElement } from 'lwc';
import HumanitixReadinessChecklist from 'c/humanitixReadinessChecklist';
import getReadiness from '@salesforce/apex/HumanitixSyncAdminController.getReadiness';

jest.mock(
  '@salesforce/apex/HumanitixSyncAdminController.getReadiness',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const ALL_OK = [
  { key: 'apiKey', label: 'API key saved', status: 'ok', message: 'An API key is saved.' },
  { key: 'schedule', label: 'Schedule', status: 'ok', message: 'A sync schedule is set.' }
];

function flush() {
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function mount() {
  const element = createElement('c-humanitix-readiness-checklist', { is: HumanitixReadinessChecklist });
  document.body.appendChild(element);
  return element;
}

describe('c-humanitix-readiness-checklist', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says everything is ready when all items pass', async () => {
    getReadiness.mockResolvedValue(ALL_OK);
    const element = mount();
    await flush();

    expect(element.shadowRoot.querySelector('.summary').textContent).toBe('Everything is ready.');
    expect(element.shadowRoot.querySelectorAll('.checklist-item')).toHaveLength(2);
  });

  it('counts and shows the items that need attention', async () => {
    getReadiness.mockResolvedValue([
      ALL_OK[0],
      { key: 'connection', label: 'Connection to Humanitix', status: 'error', message: 'Humanitix rejected the API key.' },
      { key: 'schedule', label: 'Schedule', status: 'warning', message: 'No schedule is set.' }
    ]);
    const element = mount();
    await flush();

    expect(element.shadowRoot.querySelector('.summary').textContent).toBe('2 items need attention.');
    const failing = element.shadowRoot.querySelector('[data-key="connection"]');
    expect(failing.dataset.status).toBe('error');
    expect(failing.querySelector('.item-message').textContent).toBe('Humanitix rejected the API key.');
    expect(failing.querySelector('lightning-icon').iconName).toBe('utility:error');
  });

  it('uses the singular for one item', async () => {
    getReadiness.mockResolvedValue([{ key: 'schedule', label: 'Schedule', status: 'warning', message: 'x' }]);
    const element = mount();
    await flush();

    expect(element.shadowRoot.querySelector('.summary').textContent).toBe('1 item needs attention.');
  });

  it('shows the load error', async () => {
    getReadiness.mockRejectedValue({ body: { message: 'Insufficient access' } });
    const element = mount();
    await flush();

    expect(element.shadowRoot.querySelector('.load-error').textContent).toBe('Insufficient access');
    expect(element.shadowRoot.querySelectorAll('.checklist-item')).toHaveLength(0);
  });

  it('checks again on Refresh', async () => {
    getReadiness.mockResolvedValue(ALL_OK);
    const element = mount();
    await flush();
    element.shadowRoot.querySelector('lightning-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(getReadiness).toHaveBeenCalledTimes(2);
  });
});
```

In `humanitixSetupDashboard.test.js` add the virtual mock (the dashboard now renders the checklist) and a Reason column test:

```js
jest.mock(
  '@salesforce/apex/HumanitixSyncAdminController.getReadiness',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  { virtual: true }
);
```

```js
  it('shows the run reason column', async () => {
    const element = createElement('c-humanitix-setup-dashboard', { is: HumanitixSetupDashboard });
    document.body.appendChild(element);

    isSyncEnabled.emit(true);
    getRecentRuns.emit([{ Id: 'a01', Name: 'RUN-1', Status__c: 'Failed', Error_Summary__c: 'No Humanitix API key is saved.' }]);
    await flush();

    const table = element.shadowRoot.querySelector('lightning-datatable');
    const reason = table.columns.find((c) => c.fieldName === 'Error_Summary__c');
    expect(reason.label).toBe('Reason');
    expect(element.shadowRoot.querySelector('c-humanitix-readiness-checklist')).not.toBeNull();
  });
```

- [ ] **Step 2: Run `npx sfdx-lwc-jest`**; the new tests fail (module not found).

- [ ] **Step 3: Implement.** `humanitixReadinessChecklist.html`:

```html
<template>
  <lightning-card title="Ready to sync" icon-name="standard:task2">
    <lightning-button
      slot="actions"
      label="Refresh"
      icon-name="utility:refresh"
      onclick={handleRefresh}
      disabled={isLoading}
    ></lightning-button>

    <div class="slds-p-horizontal_medium slds-p-bottom_medium">
      <template lwc:if={isLoading}>
        <lightning-spinner alternative-text="Checking the setup" size="small"></lightning-spinner>
      </template>
      <template lwc:if={loadError}>
        <p class="load-error slds-text-color_error">{loadError}</p>
      </template>
      <template lwc:elseif={hasItems}>
        <p class="summary slds-m-bottom_small">{summary}</p>
        <ul class="slds-has-dividers_bottom-space">
          <template for:each={items} for:item="item">
            <li key={item.key} class="checklist-item slds-item" data-key={item.key} data-status={item.status}>
              <div class="slds-media slds-media_center">
                <div class="slds-media__figure">
                  <lightning-icon
                    icon-name={item.iconName}
                    variant={item.iconVariant}
                    size="x-small"
                    alternative-text={item.statusText}
                  ></lightning-icon>
                </div>
                <div class="slds-media__body">
                  <p class="slds-text-title_bold">{item.label}</p>
                  <p class="item-message">{item.message}</p>
                </div>
              </div>
            </li>
          </template>
        </ul>
      </template>
    </div>
  </lightning-card>
</template>
```

`humanitixReadinessChecklist.js`:

```js
import { LightningElement } from 'lwc';
import { errorMessage } from 'c/humanitixSetupUtils';
import getReadiness from '@salesforce/apex/HumanitixSyncAdminController.getReadiness';

const ICONS = {
  ok: { iconName: 'utility:success', iconVariant: 'success', statusText: 'Ready' },
  error: { iconName: 'utility:error', iconVariant: 'error', statusText: 'Needs action' },
  warning: { iconName: 'utility:warning', iconVariant: 'warning', statusText: 'Worth a look' },
  unknown: { iconName: 'utility:info', iconVariant: undefined, statusText: 'Not checked' }
};

export default class HumanitixReadinessChecklist extends LightningElement {
  items = [];
  isLoading = false;
  loadError;

  connectedCallback() {
    this.load();
  }

  get hasItems() {
    return this.items.length > 0;
  }

  get summary() {
    const open = this.items.filter((i) => i.status !== 'ok').length;
    if (open === 0) {
      return 'Everything is ready.';
    }
    return open === 1 ? '1 item needs attention.' : `${open} items need attention.`;
  }

  async load() {
    this.isLoading = true;
    this.loadError = undefined;
    try {
      const data = await getReadiness();
      this.items = (data || []).map((i) => ({ ...i, ...(ICONS[i.status] || ICONS.unknown) }));
    } catch (error) {
      this.items = [];
      this.loadError = errorMessage(error);
    } finally {
      this.isLoading = false;
    }
  }

  handleRefresh() {
    return this.load();
  }
}
```

`humanitixReadinessChecklist.js-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<LightningComponentBundle xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>62.0</apiVersion>
    <isExposed>false</isExposed>
    <masterLabel>Humanitix Readiness Checklist</masterLabel>
    <description>Checks that the org is ready to sync and says what to fix.</description>
</LightningComponentBundle>
```

Dashboard: in `humanitixSetupDashboard.html` add `<c-humanitix-readiness-checklist class="slds-m-bottom_small"></c-humanitix-readiness-checklist>` as the first child of `<template>`. In `humanitixSetupDashboard.js` append to `COLUMNS`:

```js
  { label: 'Reason', fieldName: 'Error_Summary__c', wrapText: true }
```

- [ ] **Step 4: Run `npx sfdx-lwc-jest` and `npm run lint`**, expect all pass. Deploy to `htx-events`.
- [ ] **Step 5: Commit** `feat: Ready to sync checklist and run reason on the Dashboard`.

---

### Task 7: Documentation

**Files:**
- Modify: `docs/INSTALL.md`, `docs/CONFIGURATION.md`

- [ ] **Step 1:** In `docs/INSTALL.md`: replace every em dash with a colon, comma or period; in "Upgrading / installing over an existing source deploy" replace "(the sync retries silently, so check Setup → Apex Jobs if runs seem stuck)" with "(from 1.3.1 the run stops on its first step with *No Humanitix API key is saved*, and the Dashboard checklist shows the same)"; add after it:

```markdown
## Troubleshooting the install

Start with the **Ready to sync** checklist on the *Humanitix Setup* tab's
**Dashboard**: it checks the API key, the connection, the Marketing User and
permission set for the users who run the sync, and the schedule, and says what
to do for any item that fails.

If the install itself fails:

- **The connector was already deployed from source.** Installing over a source
  deploy normally adopts the existing components (see the section above, and
  re-enter the API key afterwards). If the install stops with an error, it names
  the component it could not install. A component that was changed in the org in
  a way the package cannot apply, for example a field whose type was changed,
  must be changed back to match the package, or removed, before you install
  again.
- **Installing an older version over a newer one.** A package cannot be
  downgraded. Install the current version instead. Going back to an older
  version means uninstalling first, which deletes the connector's objects and
  their data.
- **Right after deleting connector fields.** Salesforce keeps a deleted custom
  field, and its API name, until it is erased, so a package field of the same
  name cannot be created. In Setup, open **Object Manager**, the object,
  **Fields & Relationships**, then **Deleted Fields**, and **Erase** the field.
  Then install again.
```

- [ ] **Step 2:** In `docs/CONFIGURATION.md` section 5, after the "Monitor runs" paragraph, add:

```markdown
### Ready to sync checklist and run reasons

The **Dashboard** tab starts with a **Ready to sync** checklist: API key saved,
connection to Humanitix, Marketing User, the Humanitix Integration Admin
permission set (for you and for the users who own the scheduled jobs, since a
scheduled run runs as the user who scheduled it), and a schedule. Every item
that needs attention says what to do and where. **Refresh** checks again.

The **Sync Runs** table has a **Reason** column with a plain-language summary of
anything that went wrong in a run. Each log entry starts with the same sentence
and keeps the raw response after **Details:** for support:

| Message | What it means |
| --- | --- |
| No Humanitix API key is saved | The run stopped on its first call. Add the key on the Connection tab. |
| Humanitix rejected the API key | HTTP 401 or 403. The run stopped. Check the key, and that the user running the sync has the permission set. |
| This event no longer exists in Humanitix and was skipped | HTTP 404 on an event's orders or tickets. The event is marked archived in Salesforce and later runs skip it. This does not make the run Partial. |
| Humanitix was busy or unavailable | HTTP 429 or 5xx after all retries. The next run tries again. |
| Humanitix could not be reached | A timeout or network error after all retries. The next run tries again. |
```

- [ ] **Step 3: Check** `grep -n '—' docs/INSTALL.md` returns nothing.
- [ ] **Step 4: Commit** `docs: install troubleshooting and plain-language sync messages`.

---

### Task 8: Full verification

- [ ] Deploy `force-app` to `htx-events`; run all local tests: `sf apex run test --target-org htx-events --test-level RunLocalTests --result-format human --code-coverage --wait 30`. Expect 0 failures, org-wide coverage at least 75%.
- [ ] Run the new and changed test classes once more in a bare state: delete nothing, but confirm none of them call `useShippedMappings()` or depend on mapping records (they do not touch the mapping engine).
- [ ] `npx sfdx-lwc-jest` and `npm run lint` green.
- [ ] Open the Humanitix Setup tab in `htx-events` and check the checklist renders (no key in a scratch org shows the API key and connection items).
- [ ] Ready for the 1.3.1 build (`sf package version create ... --code-coverage`), which needs Avinash's go-ahead.
