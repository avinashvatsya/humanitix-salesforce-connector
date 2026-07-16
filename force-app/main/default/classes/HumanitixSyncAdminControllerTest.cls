@IsTest
private class HumanitixSyncAdminControllerTest {
    @IsTest
    static void runSyncNowReturnsLogId() {
        Test.startTest();
        Id logId = HumanitixSyncAdminController.runSyncNow();
        Test.stopTest();
        System.assertNotEquals(null, logId);
        System.assertEquals('Manual', [SELECT Trigger_Source__c FROM Humanitix_Sync_Log__c WHERE Id = :logId].Trigger_Source__c);
    }

    @IsTest
    static void runSyncNowThrowsWhenDisabled() {
        insert new Humanitix_Sync_Toggle__c(SetupOwnerId = UserInfo.getOrganizationId(), Sync_Enabled__c = false);
        Test.startTest();
        try {
            HumanitixSyncAdminController.runSyncNow();
            System.assert(false, 'expected AuraHandledException');
        } catch (AuraHandledException e) {
            // expected
        }
        Test.stopTest();
    }

    @IsTest
    static void getRecentRunsAndEnabledFlag() {
        HumanitixSyncLogService.start('r1', 'Manual', 'Events');
        Test.startTest();
        List<Humanitix_Sync_Log__c> runs = HumanitixSyncAdminController.getRecentRuns();
        Boolean enabled = HumanitixSyncAdminController.isSyncEnabled();
        Test.stopTest();
        System.assert(runs.size() >= 1);
        System.assertEquals(true, enabled);
    }
}
