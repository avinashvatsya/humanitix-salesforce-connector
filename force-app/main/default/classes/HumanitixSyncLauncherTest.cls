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
    static void invocableReturnsErrorStringWhenDisabled() {
        insert new Humanitix_Sync_Toggle__c(SetupOwnerId = UserInfo.getOrganizationId(), Sync_Enabled__c = false);
        Test.startTest();
        List<String> out = HumanitixSyncInvocable.run();
        Test.stopTest();
        System.assertEquals(1, out.size());
        System.assert(out[0].startsWith('ERROR:'), 'launch rejection becomes an ERROR string, got: ' + out[0]);
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

    @IsTest
    static void fullModeOverridesIncrementalConfig() {
        HumanitixSyncConfig.overrideSetting = new Humanitix_Sync_Setting__mdt(Since_Mode__c = 'Modified');
        Test.startTest();
        HumanitixSyncLauncher.start('Scheduled', HumanitixSyncLauncher.MODE_FULL);
        Test.stopTest();
        System.assertEquals(false, HumanitixSyncLauncher.lastState.incremental, 'Full mode must force a full pull');
    }

    @IsTest
    static void deltaModeOverridesFullPullConfig() {
        HumanitixSyncConfig.overrideSetting = new Humanitix_Sync_Setting__mdt(Since_Mode__c = 'FullPull');
        Test.startTest();
        HumanitixSyncLauncher.start('Scheduled', HumanitixSyncLauncher.MODE_DELTA);
        Test.stopTest();
        System.assertEquals(true, HumanitixSyncLauncher.lastState.incremental, 'Delta mode must force incremental');
    }

    @IsTest
    static void nullModeFollowsConfig() {
        HumanitixSyncConfig.overrideSetting = new Humanitix_Sync_Setting__mdt(Since_Mode__c = 'FullPull');
        Test.startTest();
        HumanitixSyncLauncher.start('Manual');
        Test.stopTest();
        System.assertEquals(false, HumanitixSyncLauncher.lastState.incremental, 'No mode must follow Since_Mode__c');
    }

    @IsTest
    static void schedulerCarriesItsModeIntoTheRun() {
        HumanitixSyncConfig.overrideSetting = new Humanitix_Sync_Setting__mdt(Since_Mode__c = 'Modified');
        Test.startTest();
        new HumanitixSyncScheduler(HumanitixSyncLauncher.MODE_FULL).execute(null);
        Test.stopTest();
        System.assertEquals(false, HumanitixSyncLauncher.lastState.incremental, 'Daily full job must run full');
        System.assertEquals(1, [SELECT COUNT() FROM Humanitix_Sync_Log__c WHERE Trigger_Source__c = 'Scheduled']);
    }

    @IsTest
    static void selectedModeSnapshotsTheIds() {
        HumanitixSyncConfig.overrideSetting = new Humanitix_Sync_Setting__mdt(
            Event_Selection__c = 'Selected',
            Selected_Event_Ids__c = 'evt_1,evt_2',
            In_Future_Only__c = true
        );
        Test.startTest();
        HumanitixSyncLauncher.start('Manual');
        Test.stopTest();
        HumanitixSyncState st = HumanitixSyncLauncher.lastState;
        System.assertEquals('Selected', st.eventSelection);
        System.assertEquals(new List<String>{ 'evt_1', 'evt_2' }, st.selectedEventIds);
        System.assertEquals(false, st.inFutureOnly, 'Selected mode never sends inFutureOnly');
    }

    @IsTest
    static void futureOnlyModeSetsInFutureOnly() {
        HumanitixSyncConfig.overrideSetting = new Humanitix_Sync_Setting__mdt(Event_Selection__c = 'FutureOnly');
        Test.startTest();
        HumanitixSyncLauncher.start('Manual');
        Test.stopTest();
        System.assertEquals('FutureOnly', HumanitixSyncLauncher.lastState.eventSelection);
        System.assertEquals(true, HumanitixSyncLauncher.lastState.inFutureOnly);
        System.assertEquals(new List<String>(), HumanitixSyncLauncher.lastState.selectedEventIds);
    }

    @IsTest
    static void selectedModeWithNoIdsRefusesToStart() {
        HumanitixSyncConfig.overrideSetting = new Humanitix_Sync_Setting__mdt(Event_Selection__c = 'Selected');
        Test.startTest();
        try {
            HumanitixSyncLauncher.start('Manual');
            System.assert(false, 'expected LaunchException');
        } catch (HumanitixSyncLauncher.LaunchException e) {
            System.assert(e.getMessage().startsWith('Event Selection is Selected but no events are selected'), e.getMessage());
        }
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM Humanitix_Sync_Log__c], 'No run log may be created');
    }

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
}
