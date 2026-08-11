@IsTest
private class HumanitixSyncConfigTest {
    @IsTest
    static void defaultsFromShippedSetting() {
        // The org's Default Humanitix Sync Setting is visible in tests, and the
        // Sync Settings tab lets admins edit it, so assert invariants rather
        // than shipped literals (fallback literals are covered below).
        System.assert(HumanitixSyncConfig.pageSize() >= 1);
        System.assert(String.isNotBlank(HumanitixSyncConfig.namedCredentialName()));
        System.assert(HumanitixSyncConfig.maxRetries() >= 0);
        List<String> r = HumanitixSyncConfig.enabledResources();
        System.assert(r.size() > 0);
        // canonical order: whatever subset is enabled must follow Tags, Events, Orders, Tickets
        List<Integer> positions = new List<Integer>();
        for (String resource : r) {
            positions.add(HumanitixSyncConfig.CANONICAL_ORDER.indexOf(resource));
        }
        for (Integer i = 1; i < positions.size(); i++) {
            System.assert(positions[i] > positions[i - 1], 'Resources out of canonical order: ' + r);
        }
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
