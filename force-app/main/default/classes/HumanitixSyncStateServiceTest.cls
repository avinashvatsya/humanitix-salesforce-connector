@IsTest
private class HumanitixSyncStateServiceTest {
    @IsTest
    static void promoteThenReadCursor() {
        Datetime wm = Datetime.newInstanceGmt(2026, 1, 1, 0, 0, 0);
        HumanitixSyncStateService.promote('events', 'Event', null, 'run-1', wm);
        System.assertEquals(wm, HumanitixSyncStateService.getCursor('events'));
        // idempotent upsert on the same key
        Datetime wm2 = Datetime.newInstanceGmt(2026, 2, 1, 0, 0, 0);
        HumanitixSyncStateService.promote('events', 'Event', null, 'run-2', wm2);
        System.assertEquals(wm2, HumanitixSyncStateService.getCursor('events'));
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Sync_State__c WHERE Cursor_Key__c = 'events']);
    }

    @IsTest
    static void missingCursorIsNull() {
        System.assertEquals(null, HumanitixSyncStateService.getCursor('orders:none'));
    }

    @IsTest
    static void recordFailureIncrementsWithoutMovingWatermark() {
        Datetime wm = Datetime.newInstanceGmt(2026, 1, 1, 0, 0, 0);
        HumanitixSyncStateService.promote('tickets:e1', 'Ticket', 'e1', 'run-1', wm);
        HumanitixSyncStateService.recordFailure('tickets:e1', 'Ticket', 'e1', 'run-2');
        HumanitixSyncStateService.recordFailure('tickets:e1', 'Ticket', 'e1', 'run-3');
        Humanitix_Sync_State__c s = [
            SELECT Consecutive_Failures__c, Last_Successful_Sync__c, Last_Status__c
            FROM Humanitix_Sync_State__c
            WHERE Cursor_Key__c = 'tickets:e1'
        ];
        System.assertEquals(2, s.Consecutive_Failures__c);
        System.assertEquals(wm, s.Last_Successful_Sync__c, 'watermark must not move on failure');
        System.assertEquals('Failed', s.Last_Status__c);
    }

    @IsTest
    static void nextEventIdKeysetIterates() {
        insert new List<Humanitix_Event__c>{
            new Humanitix_Event__c(Name = 'A', Humanitix_Id__c = 'evt_a', Is_Archived__c = false),
            new Humanitix_Event__c(Name = 'B', Humanitix_Id__c = 'evt_b', Is_Archived__c = false),
            new Humanitix_Event__c(Name = 'C', Humanitix_Id__c = 'evt_c', Is_Archived__c = true)
        };
        String first = HumanitixSyncStateService.nextEventId(null);
        System.assertEquals('evt_a', first);
        System.assertEquals('evt_b', HumanitixSyncStateService.nextEventId('evt_a'));
        System.assertEquals(null, HumanitixSyncStateService.nextEventId('evt_b'), 'archived event is skipped and there is no more');
    }
}
