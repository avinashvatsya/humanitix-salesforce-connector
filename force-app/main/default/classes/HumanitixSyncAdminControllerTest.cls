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
    static void ensureDefaultMappingsSeedsWhenAnyDefaultIsMissing() {
        // Deterministic in every org: a fully seeded org has nothing missing; a
        // bare org or an org upgraded to a version with new defaults does.
        Boolean anyMissing = !HumanitixMappingSeeder.missingDefaults().isEmpty();

        Test.startTest();
        Boolean first = HumanitixSyncAdminController.ensureDefaultMappings();
        Boolean second = HumanitixSyncAdminController.ensureDefaultMappings();
        Test.stopTest();

        System.assertEquals(anyMissing, first, 'seeding must start exactly when a shipped default is missing');
        System.assertEquals(first, second, 'repeat calls report the same state');
        System.assertEquals(
            anyMissing ? 1 : 0,
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

    @IsTest
    static void getReadinessReturnsTheChecklist() {
        Test.startTest();
        List<HumanitixReadinessService.Item> items = HumanitixSyncAdminController.getReadiness();
        Test.stopTest();
        System.assertEquals(5, items.size());
    }
}
