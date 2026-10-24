/**
 * Step-level tests for the sync worker. Each transaction (test method) exercises
 * ONE step; multi-step chains are covered by asserting the mutated state and the DB
 * effect of each step in isolation.
 *
 * Prerequisite data (a Marketing User, a run log, and an event) is created in
 * @TestSetup — committed before the method runs — so there is no DML in the test
 * method before the mocked callout, and Campaign/Campaign Member writes happen under
 * a Marketing User.
 */
@IsTest
private class HumanitixSyncQueueableTest {
    @TestSetup
    static void setup() {
        HumanitixTestDataFactory.insertMarketingAdmin(); // isolated setup-object DML
        HumanitixSyncLogService.start('test-run', 'Manual', 'Tags,Events,Orders,Tickets');
        insert new Humanitix_Event__c(
            Name = 'E',
            Humanitix_Id__c = HumanitixTestDataFactory.EVENT_ID,
            Is_Archived__c = false
        );
    }

    private static HumanitixSyncState baseState(List<String> phases) {
        Humanitix_Sync_Log__c log = [SELECT Id FROM Humanitix_Sync_Log__c ORDER BY CreatedDate DESC LIMIT 1];
        HumanitixSyncState st = new HumanitixSyncState();
        st.runId = 'test-run';
        st.logId = log.Id;
        st.runStart = Datetime.now();
        st.phases = phases;
        st.phaseIndex = 0;
        st.page = 1;
        st.pageSize = 100;
        st.maxRetries = 5;
        st.retryDelayMinutes = 5;
        st.incremental = true;
        st.namedCredential = 'HumanitixAPI';
        return st;
    }

    private static String page(String field, String json) {
        return HumanitixTestDataFactory.pageBody(field, json, 1, 1, 100);
    }

    @IsTest
    static void tagsStepMapsAndAdvances() {
        HumanitixTestDataFactory.useShippedMappings();
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(200, page('tags', HumanitixTestDataFactory.tagJson())));
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Tags', 'Events' }));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = null;
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            oc = q.runStep();
        }
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.PROCEED, oc);
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'tag_1']);
        System.assertEquals(1, q.getState().phaseIndex, 'should advance from Tags to Events');
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Sync_Log_Entry__c WHERE Resource__c = 'Tag']);
    }

    @IsTest
    static void eventsStepPromotesCursorAndFinalizes() {
        HumanitixTestDataFactory.useShippedMappings();
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(200, page('events', HumanitixTestDataFactory.eventJson())));
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Events' }));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = null;
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            oc = q.runStep();
        }
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.DONE, oc);
        System.assertEquals(1, [SELECT COUNT() FROM Campaign WHERE Humanitix_Event_Id__c = :HumanitixTestDataFactory.EVENT_ID]);
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Sync_State__c WHERE Cursor_Key__c = 'events']);
        System.assertEquals('Success', [SELECT Status__c FROM Humanitix_Sync_Log__c WHERE Id = :q.getState().logId].Status__c);
    }

    @IsTest
    static void ordersStepResolvesEventAndMaps() {
        HumanitixTestDataFactory.useShippedMappings();
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(200, page('orders', HumanitixTestDataFactory.orderJson())));
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Orders' }));

        Test.startTest();
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            q.runStep();
        }
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Order__c WHERE Humanitix_Id__c = :HumanitixTestDataFactory.ORDER_ID]);
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE Humanitix_Contact_Key__c = 'frodo@shire.com']);
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Sync_State__c WHERE Cursor_Key__c = :('orders:' + HumanitixTestDataFactory.EVENT_ID)]);
    }

    @IsTest
    static void retryableStatusReturnsRetry() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(429, '', '30'));
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Events' }));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = q.runStep();
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.RETRY, oc);
        System.assertEquals(1, q.getState().attempt);
        System.assert(q.getState().retryDelay >= 1);
    }

    @IsTest
    static void fatalStatusLogsFailureAndFinalizes() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(404, '{"message":"nope"}'));
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Events' }));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = q.runStep();
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.DONE, oc);
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Sync_Log_Entry__c WHERE Status__c = 'Failed']);
        System.assertEquals('Failed', [SELECT Status__c FROM Humanitix_Sync_Log__c WHERE Id = :q.getState().logId].Status__c);
    }

    @IsTest
    static void exhaustedRetriesAdvances() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(503, ''));
        HumanitixSyncState st = baseState(new List<String>{ 'Events' });
        st.maxRetries = 1;
        st.attempt = 1; // next retryable => attempt 2 > max 1
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(st);

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = q.runStep();
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.DONE, oc);
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Sync_Log_Entry__c WHERE Status__c = 'Failed']);
    }

    @IsTest
    static void calloutExceptionRetries() {
        // HumanitixCalloutMock with no enqueued responses still returns 200; to force
        // a CalloutException we set a mock that throws.
        Test.setMock(HttpCalloutMock.class, new ThrowingMock());
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Events' }));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = q.runStep();
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.RETRY, oc, 'a transient callout error should retry, not skip');
        System.assertEquals(1, q.getState().attempt);
    }

    @IsTest
    static void killSwitchFinalizesImmediately() {
        insert new Humanitix_Sync_Toggle__c(SetupOwnerId = UserInfo.getOrganizationId(), Sync_Enabled__c = false);
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Events' }));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = q.runStep();
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.DONE, oc);
    }

    @IsTest
    static void emptyPhaseListFinalizesImmediately() {
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>()));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = q.runStep();
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.DONE, oc);
    }

    @IsTest
    static void ordersPhaseWithNoEventsAdvances() {
        delete [SELECT Id FROM Humanitix_Event__c];
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Orders' }));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = q.runStep();
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.DONE, oc, 'no events to iterate -> phase ends the run');
    }

    @IsTest
    static void ticketsStepBuildsFilteredRequestAndAdvances() {
        Test.setMock(
            HttpCalloutMock.class,
            new HumanitixCalloutMock().enqueue(200, HumanitixTestDataFactory.pageBody('tickets', '', 0, 1, 100))
        );
        HumanitixSyncState st = baseState(new List<String>{ 'Tickets' });
        st.ticketStatusFilter = 'complete';
        st.incremental = false; // non-incremental path skips the since cursor
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(st);

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = null;
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            oc = q.runStep();
        }
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.DONE, oc, 'empty tickets page for the only event ends the run');
    }

    @IsTest
    static void executeRunsAStep() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(200, '{"total":0,"page":1,"pageSize":100,"events":[]}'));
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Events' }));

        Test.startTest();
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            q.execute(null);
        }
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Sync_Log_Entry__c WHERE Resource__c = 'Event']);
    }

    private class ThrowingMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            throw new System.CalloutException('Read timed out');
        }
    }

    private static HumanitixSyncState selectedState(List<String> phases, List<String> ids) {
        HumanitixSyncState st = baseState(phases);
        st.eventSelection = 'Selected';
        st.selectedEventIds = ids;
        return st;
    }

    @IsTest
    static void selectedModeDropsUnselectedEventsBeforeMapping() {
        HumanitixTestDataFactory.useShippedMappings();
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(200, page('events', HumanitixTestDataFactory.eventJson())));
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(selectedState(new List<String>{ 'Events' }, new List<String>{ 'evt_other' }));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = null;
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            oc = q.runStep();
        }
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.DONE, oc);
        System.assertEquals(0, [SELECT COUNT() FROM Campaign WHERE Humanitix_Event_Id__c = :HumanitixTestDataFactory.EVENT_ID], 'Unselected events create nothing');
        Humanitix_Sync_Log_Entry__c entry = [SELECT Status__c, Records_Processed__c, Error_Message__c FROM Humanitix_Sync_Log_Entry__c WHERE Resource__c = 'Event'];
        System.assertEquals('Success', entry.Status__c);
        System.assertEquals(0, entry.Records_Processed__c);
        System.assert(entry.Error_Message__c.contains('1 event(s) not selected, skipped'), entry.Error_Message__c);
        System.assertEquals(0, [SELECT COUNT() FROM Humanitix_Sync_State__c WHERE Cursor_Key__c = 'events'], 'Selected mode never moves the events cursor');
    }

    @IsTest
    static void selectedModeKeepsSelectedEvents() {
        HumanitixTestDataFactory.useShippedMappings();
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(200, page('events', HumanitixTestDataFactory.eventJson())));
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(
            selectedState(new List<String>{ 'Events' }, new List<String>{ HumanitixTestDataFactory.EVENT_ID })
        );

        Test.startTest();
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            q.runStep();
        }
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Campaign WHERE Humanitix_Event_Id__c = :HumanitixTestDataFactory.EVENT_ID]);
        System.assertEquals(null, [SELECT Error_Message__c FROM Humanitix_Sync_Log_Entry__c WHERE Resource__c = 'Event'].Error_Message__c);
    }

    @IsTest
    static void selectedModeOrdersSkipUnselectedEventsWithoutACallout() {
        HumanitixCalloutMock mock = new HumanitixCalloutMock().enqueue(200, page('orders', HumanitixTestDataFactory.orderJson()));
        Test.setMock(HttpCalloutMock.class, mock);
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(selectedState(new List<String>{ 'Orders' }, new List<String>{ 'evt_other' }));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = q.runStep();
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.DONE, oc, 'The only staged event is unselected, so the phase ends');
        System.assertEquals(0, mock.requestedEndpoints.size(), 'No callout for an unselected event');
    }

    @IsTest
    static void nextEventIdHonoursTheSelection() {
        insert new Humanitix_Event__c(Name = 'Z', Humanitix_Id__c = 'evt_zzz', Is_Archived__c = false);
        System.assertEquals(HumanitixTestDataFactory.EVENT_ID, HumanitixSyncStateService.nextEventId(null), 'no filter');
        System.assertEquals('evt_zzz', HumanitixSyncStateService.nextEventId(null, new Set<String>{ 'evt_zzz' }));
        System.assertEquals(null, HumanitixSyncStateService.nextEventId('evt_zzz', new Set<String>{ 'evt_zzz' }));
        System.assertEquals(null, HumanitixSyncStateService.nextEventId(null, new Set<String>()), 'empty filter matches nothing');
    }

    @IsTest
    static void selectedModeAlwaysListsEventsInFull() {
        HumanitixSyncStateService.promote('events', 'Event', null, 'earlier-run', Datetime.now().addDays(-1));
        HumanitixTestDataFactory.useShippedMappings();
        HumanitixCalloutMock mock = new HumanitixCalloutMock().enqueue(200, page('events', HumanitixTestDataFactory.eventJson()));
        Test.setMock(HttpCalloutMock.class, mock);
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(
            selectedState(new List<String>{ 'Events' }, new List<String>{ HumanitixTestDataFactory.EVENT_ID })
        );

        Test.startTest();
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            q.runStep();
        }
        Test.stopTest();

        System.assert(!mock.requestedEndpoints[0].contains('since='), 'Selected mode must not filter the events listing by the cursor: ' + mock.requestedEndpoints[0]);
    }

    @IsTest
    static void allModeStillSendsTheEventsCursor() {
        HumanitixSyncStateService.promote('events', 'Event', null, 'earlier-run', Datetime.now().addDays(-1));
        HumanitixTestDataFactory.useShippedMappings();
        HumanitixCalloutMock mock = new HumanitixCalloutMock().enqueue(200, page('events', HumanitixTestDataFactory.eventJson()));
        Test.setMock(HttpCalloutMock.class, mock);
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Events' }));

        Test.startTest();
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            q.runStep();
        }
        Test.stopTest();

        System.assert(mock.requestedEndpoints[0].contains('since='), mock.requestedEndpoints[0]);
    }

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
}
