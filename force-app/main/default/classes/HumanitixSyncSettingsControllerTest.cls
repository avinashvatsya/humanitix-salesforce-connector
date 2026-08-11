@IsTest
private class HumanitixSyncSettingsControllerTest {
    private static HumanitixSyncSettingsController.SettingsDto validDto() {
        HumanitixSyncSettingsController.SettingsDto dto = new HumanitixSyncSettingsController.SettingsDto();
        dto.pageSize = 50;
        dto.enabledResources = new List<String>{ 'Events', 'Orders' };
        dto.inFutureOnly = true;
        dto.ticketStatusFilter = null;
        dto.maxRetries = 3;
        dto.retryDelayMinutes = 10;
        dto.sinceMode = 'FullPull';
        dto.namedCredentialName = 'HumanitixAPI';
        return dto;
    }

    @IsTest
    static void getSyncSettingsReadsThroughConfig() {
        HumanitixSyncConfig.overrideSetting = new Humanitix_Sync_Setting__mdt(
            Page_Size__c = 42,
            Enabled_Resources__c = 'Events,Tags',
            In_Future_Only__c = true,
            Max_Retries__c = 2,
            Retry_Delay_Minutes__c = 7,
            Since_Mode__c = 'FullPull'
        );

        HumanitixSyncSettingsController.SettingsDto dto = HumanitixSyncSettingsController.getSyncSettings();

        System.assertEquals(42, dto.pageSize);
        System.assertEquals(new List<String>{ 'Tags', 'Events' }, dto.enabledResources, 'Canonical order expected');
        System.assertEquals(true, dto.inFutureOnly);
        System.assertEquals(2, dto.maxRetries);
        System.assertEquals(7, dto.retryDelayMinutes);
        System.assertEquals('FullPull', dto.sinceMode);
        System.assertEquals('HumanitixAPI', dto.namedCredentialName, 'Blank falls back to default');
        // Same computation as the controller so the test passes with or without
        // CMT records in the org (dev org vs bare package-build org).
        Boolean orgHasRecord = Humanitix_Sync_Setting__mdt.getInstance('Default') != null;
        System.assertEquals(orgHasRecord, dto.recordExists);
    }

    @IsTest
    static void saveDeploysFullFieldSet() {
        Test.startTest();
        String jobId = HumanitixSyncSettingsController.saveSyncSettings(JSON.serialize(validDto()));
        Test.stopTest();

        System.assertEquals(null, jobId, 'Deploy returns null in test context');
        System.assertEquals('Sync Settings', HumanitixMetadataWriter.lastPurpose);
        List<Metadata.Metadata> deployed = HumanitixMetadataWriter.lastContainer.getMetadata();
        System.assertEquals(1, deployed.size());
        Metadata.CustomMetadata cmt = (Metadata.CustomMetadata) deployed[0];
        System.assertEquals('Humanitix_Sync_Setting.Default', cmt.fullName);

        Map<String, Object> byField = new Map<String, Object>();
        for (Metadata.CustomMetadataValue v : cmt.values) {
            byField.put(v.field, v.value);
        }
        System.assertEquals(8, byField.size(), 'All live settings fields must be sent, nulls included');
        System.assertEquals('Events,Orders', byField.get('Enabled_Resources__c'));
        System.assertEquals(50, byField.get('Page_Size__c'));
        System.assert(byField.containsKey('Ticket_Status_Filter__c'), 'Cleared field must still deploy');
        System.assertEquals(null, byField.get('Ticket_Status_Filter__c'));
        System.assertEquals('FullPull', byField.get('Since_Mode__c'));
    }

    @IsTest
    static void saveRejectsInvalidSettings() {
        HumanitixSyncSettingsController.SettingsDto dto = validDto();
        dto.pageSize = 0;
        dto.enabledResources = new List<String>();
        dto.sinceMode = 'Sometimes';

        Boolean threw = false;
        try {
            HumanitixSyncSettingsController.saveSyncSettings(JSON.serialize(dto));
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Invalid settings must be rejected');
        List<String> problems = HumanitixSyncSettingsController.validate(dto);
        System.assertEquals(3, problems.size(), String.join(problems, ' | '));
    }

    @IsTest
    static void validateFlagsUnknownResourceAndRanges() {
        HumanitixSyncSettingsController.SettingsDto dto = validDto();
        dto.enabledResources = new List<String>{ 'Events', 'Bananas' };
        dto.maxRetries = 99;
        dto.retryDelayMinutes = 0;

        List<String> problems = HumanitixSyncSettingsController.validate(dto);
        System.assertEquals(3, problems.size(), String.join(problems, ' | '));
    }

    @IsTest
    static void saveRejectsUnreadablePayload() {
        Boolean threw = false;
        try {
            HumanitixSyncSettingsController.saveSyncSettings('not json at all');
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw);
    }

    @IsTest
    static void killSwitchCreatesAndFlipsOrgDefault() {
        System.assertEquals(true, HumanitixSyncSettingsController.getSyncEnabled(), 'No record means enabled');

        Test.startTest();
        HumanitixSyncSettingsController.setSyncEnabled(false);
        System.assertEquals(false, HumanitixSyncSettingsController.getSyncEnabled());
        HumanitixSyncSettingsController.setSyncEnabled(true);
        System.assertEquals(true, HumanitixSyncSettingsController.getSyncEnabled());
        Test.stopTest();

        Humanitix_Sync_Toggle__c toggle = Humanitix_Sync_Toggle__c.getOrgDefaults();
        System.assertNotEquals(null, toggle.Id, 'Org default row must exist after toggling');
        System.assertEquals(true, toggle.Sync_Enabled__c);
    }
}
