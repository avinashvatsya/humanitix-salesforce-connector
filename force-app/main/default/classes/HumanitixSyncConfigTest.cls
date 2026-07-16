@IsTest
private class HumanitixSyncConfigTest {
    @IsTest
    static void defaultsFromShippedSetting() {
        // The packaged Default Humanitix Sync Setting is visible in tests.
        System.assertEquals(100, HumanitixSyncConfig.pageSize());
        System.assertEquals('HumanitixAPI', HumanitixSyncConfig.namedCredentialName());
        System.assert(HumanitixSyncConfig.maxRetries() >= 1);
        System.assert(HumanitixSyncConfig.enabledResources().size() > 0);
        // canonical order: Tags before Events before Orders before Tickets
        List<String> r = HumanitixSyncConfig.enabledResources();
        System.assertEquals('Tags', r[0]);
    }

    @IsTest
    static void overrideAppliesDefaultsForNulls() {
        HumanitixSyncConfig.overrideSetting = new Humanitix_Sync_Setting__mdt(); // all null
        System.assertEquals(100, HumanitixSyncConfig.pageSize(), 'null page size falls back to 100');
        System.assertEquals('HumanitixAPI', HumanitixSyncConfig.namedCredentialName());
        System.assertEquals(5, HumanitixSyncConfig.maxRetries());
        System.assertEquals('Modified', HumanitixSyncConfig.sinceMode());
        System.assert(HumanitixSyncConfig.incrementalEnabled());
        System.assertEquals(4, HumanitixSyncConfig.enabledResources().size(), 'blank enabled resources => all four');
    }

    @IsTest
    static void enabledResourcesRespectsCanonicalOrder() {
        HumanitixSyncConfig.overrideSetting = new Humanitix_Sync_Setting__mdt(
            Enabled_Resources__c = 'Tickets, Events'
        );
        List<String> r = HumanitixSyncConfig.enabledResources();
        System.assertEquals(2, r.size());
        System.assertEquals('Events', r[0]);
        System.assertEquals('Tickets', r[1]);
    }

    @IsTest
    static void syncEnabledDefaultsTrueAndHonorsToggle() {
        System.assertEquals(true, HumanitixSyncConfig.syncEnabled());
        insert new Humanitix_Sync_Toggle__c(SetupOwnerId = UserInfo.getOrganizationId(), Sync_Enabled__c = false);
        System.assertEquals(false, HumanitixSyncConfig.syncEnabled());
    }
}
