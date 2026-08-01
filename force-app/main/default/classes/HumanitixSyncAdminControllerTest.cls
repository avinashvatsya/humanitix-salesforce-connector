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
    static void ensureDefaultMappingsSeedsOnlyWhenRecordsMissing() {
        // Deterministic in both worlds: a dev org already has mapping records
        // (no seeding), the bare package-build org has none (seeding starts).
        Boolean orgHasRecords = [SELECT COUNT() FROM Humanitix_Object_Mapping__mdt] > 0;

        Test.startTest();
        Boolean first = HumanitixSyncAdminController.ensureDefaultMappings();
        Boolean second = HumanitixSyncAdminController.ensureDefaultMappings();
        Test.stopTest();

        System.assertEquals(!orgHasRecords, first, 'seeding must start exactly when no mapping records exist');
        System.assertEquals(first, second, 'repeat calls report the same state');
        System.assertEquals(
            orgHasRecords ? 0 : 1,
            [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'HumanitixMappingSeeder' AND JobType = 'Queueable'],
            'the seeder must be enqueued once at most while a job is already in flight'
        );
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
