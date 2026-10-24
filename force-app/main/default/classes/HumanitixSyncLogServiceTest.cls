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
