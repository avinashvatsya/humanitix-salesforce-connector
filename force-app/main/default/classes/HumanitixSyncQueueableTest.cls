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
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(200, page('tags', HumanitixTestDataFactory.tagJson())));
        HumanitixSyncQueueable q = new HumanitixSyncQueueable(baseState(new List<String>{ 'Tags', 'Events' }));

        Test.startTest();
        HumanitixSyncQueueable.StepOutcome oc = null;
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            oc = q.runStep();
        }
        Test.stopTest();

        System.assertEquals(HumanitixSyncQueueable.StepOutcome.CONTINUE, oc);
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'tag_1']);
        System.assertEquals(1, q.getState().phaseIndex, 'should advance from Tags to Events');
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Sync_Log_Entry__c WHERE Resource__c = 'Tag']);
    }

    @IsTest
    static void eventsStepPromotesCursorAndFinalizes() {
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
}
