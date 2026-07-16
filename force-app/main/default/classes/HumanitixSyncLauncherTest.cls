@IsTest
private class HumanitixSyncLauncherTest {
    @IsTest
    static void startCreatesRunningLog() {
        Test.startTest();
        Id logId = HumanitixSyncLauncher.start('Manual');
        Test.stopTest();
        Humanitix_Sync_Log__c log = [
            SELECT Status__c, Trigger_Source__c, Resources_Requested__c, Run_Id__c
            FROM Humanitix_Sync_Log__c
            WHERE Id = :logId
        ];
        System.assertEquals('Running', log.Status__c);
        System.assertEquals('Manual', log.Trigger_Source__c);
        System.assert(String.isNotBlank(log.Run_Id__c));
        System.assert(log.Resources_Requested__c.contains('Events'));
    }

    @IsTest
    static void rejectsWhenDisabled() {
        insert new Humanitix_Sync_Toggle__c(SetupOwnerId = UserInfo.getOrganizationId(), Sync_Enabled__c = false);
        Test.startTest();
        try {
            HumanitixSyncLauncher.start('Manual');
            System.assert(false, 'expected LaunchException');
        } catch (HumanitixSyncLauncher.LaunchException e) {
            System.assert(e.getMessage().containsIgnoreCase('disabled'));
        }
        Test.stopTest();
    }

    @IsTest
    static void rejectsOverlap() {
        // an in-progress run from "just now" blocks a second launch
        HumanitixSyncLogService.start('existing', 'Scheduled', 'Events');
        Test.startTest();
        try {
            HumanitixSyncLauncher.start('Manual');
            System.assert(false, 'expected LaunchException');
        } catch (HumanitixSyncLauncher.LaunchException e) {
            System.assert(e.getMessage().containsIgnoreCase('already running'));
        }
        Test.stopTest();
    }

    @IsTest
    static void schedulerExecuteStartsRun() {
        Test.startTest();
        new HumanitixSyncScheduler().execute(null);
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Sync_Log__c WHERE Trigger_Source__c = 'Scheduled']);
    }

    @IsTest
    static void schedulerExecuteSwallowsOverlap() {
        HumanitixSyncLogService.start('existing', 'Scheduled', 'Events');
        Test.startTest();
        new HumanitixSyncScheduler().execute(null); // overlap -> swallowed, no exception
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Sync_Log__c WHERE Status__c = 'Running']);
    }

    @IsTest
    static void invocableReturnsLogId() {
        Test.startTest();
        List<String> out = HumanitixSyncInvocable.run();
        Test.stopTest();
        System.assertEquals(1, out.size());
        System.assert(String.isNotBlank(out[0]));
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Sync_Log__c WHERE Trigger_Source__c = 'Invocable']);
    }

    @IsTest
    static void scheduleRegistersCronJob() {
        Test.startTest();
        Id jobId = HumanitixSyncScheduler.schedule('Humanitix Test Sync', '0 0 2 * * ?');
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM CronTrigger WHERE Id = :jobId]);
    }
}
