@IsTest
private class HumanitixSyncSettingsControllerTest {
    private static HumanitixSyncSettingsController.SettingsDto validDto() {
        HumanitixSyncSettingsController.SettingsDto dto = new HumanitixSyncSettingsController.SettingsDto();
        dto.pageSize = 50;
        dto.enabledResources = new List<String>{ 'Events', 'Orders' };
        dto.eventSelection = 'All';
        dto.selectedEventIds = new List<String>();
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
        System.assertEquals('FutureOnly', dto.eventSelection, 'Legacy checkbox resolves to FutureOnly');
        System.assertEquals(new List<String>(), dto.selectedEventIds);
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
        System.assertEquals(10, byField.size(), 'All live settings fields must be sent, nulls included');
        System.assertEquals('All', byField.get('Event_Selection__c'));
        System.assert(byField.containsKey('Selected_Event_Ids__c'));
        System.assertEquals(null, byField.get('Selected_Event_Ids__c'), 'An empty selection deploys an explicit null');
        System.assertEquals(false, byField.get('In_Future_Only__c'));
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

    private static Map<String, Object> deployedSettingValues() {
        for (Metadata.Metadata md : HumanitixMetadataWriter.lastContainer.getMetadata()) {
            Metadata.CustomMetadata cmt = (Metadata.CustomMetadata) md;
            if (cmt.fullName == 'Humanitix_Sync_Setting.Default') {
                Map<String, Object> byField = new Map<String, Object>();
                for (Metadata.CustomMetadataValue v : cmt.values) {
                    byField.put(v.field, v.value);
                }
                return byField;
            }
        }
        return null;
    }

    @IsTest
    static void saveWritesSelectedIdsAndKeepsTheLegacyCheckboxTruthful() {
        HumanitixSyncSettingsController.SettingsDto dto = validDto();
        dto.eventSelection = 'Selected';
        dto.selectedEventIds = new List<String>{ ' evt_1', 'evt_2', 'evt_1' };

        Test.startTest();
        HumanitixSyncSettingsController.saveSyncSettings(JSON.serialize(dto));
        Test.stopTest();

        Map<String, Object> byField = deployedSettingValues();
        System.assertEquals('Selected', byField.get('Event_Selection__c'));
        System.assertEquals('evt_1,evt_2', byField.get('Selected_Event_Ids__c'), 'Trimmed and de-duplicated');
        System.assertEquals(false, byField.get('In_Future_Only__c'));
    }

    @IsTest
    static void saveOfFutureOnlySetsTheLegacyCheckbox() {
        HumanitixSyncSettingsController.SettingsDto dto = validDto();
        dto.eventSelection = 'FutureOnly';

        Test.startTest();
        HumanitixSyncSettingsController.saveSyncSettings(JSON.serialize(dto));
        Test.stopTest();

        System.assertEquals(true, deployedSettingValues().get('In_Future_Only__c'));
    }

    @IsTest
    static void validateEventSelectionRules() {
        HumanitixSyncSettingsController.SettingsDto dto = validDto();
        dto.eventSelection = 'Some';
        System.assertEquals(1, HumanitixSyncSettingsController.validate(dto).size(), 'unknown mode');

        dto.eventSelection = 'Selected';
        dto.selectedEventIds = new List<String>{ '  ' };
        List<String> problems = HumanitixSyncSettingsController.validate(dto);
        System.assertEquals(1, problems.size(), String.join(problems, ' | '));
        System.assert(problems[0].startsWith('Select at least one event'), problems[0]);

        dto.selectedEventIds = new List<String>{ 'evt_1', 'bad id; drop' };
        problems = HumanitixSyncSettingsController.validate(dto);
        System.assertEquals(1, problems.size(), String.join(problems, ' | '));
        System.assert(problems[0].contains('is not a valid Humanitix event id'), problems[0]);

        List<String> tooMany = new List<String>();
        for (Integer i = 0; i <= HumanitixSyncSettingsController.MAX_SELECTED_EVENTS; i++) {
            tooMany.add('evt_' + i);
        }
        dto.selectedEventIds = tooMany;
        problems = HumanitixSyncSettingsController.validate(dto);
        System.assertEquals(1, problems.size(), String.join(problems, ' | '));
        System.assert(problems[0].startsWith('Select at most 1000 events'), problems[0]);

        dto.eventSelection = 'All';
        dto.selectedEventIds = new List<String>();
        System.assertEquals(0, HumanitixSyncSettingsController.validate(dto).size(), 'All needs no ids');
    }

    @IsTest
    static void fetchHumanitixEventsMapsAPage() {
        HumanitixCalloutMock mock = new HumanitixCalloutMock().enqueue(
            200,
            HumanitixTestDataFactory.pageBody('events', HumanitixTestDataFactory.eventJson(), 150, 1, 100)
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        HumanitixSyncSettingsController.EventPageDto result = HumanitixSyncSettingsController.fetchHumanitixEvents(1);
        Test.stopTest();

        System.assertEquals(1, result.page);
        System.assertEquals(true, result.hasNextPage, '1 x 100 < 150');
        System.assertEquals(1, result.events.size());
        HumanitixSyncSettingsController.EventSummary e = result.events[0];
        System.assertEquals(HumanitixTestDataFactory.EVENT_ID, e.id);
        System.assertEquals('Hobbit Dance Off', e.name);
        System.assertEquals('2026-03-01T13:30:00.000Z', e.startDate);
        System.assertEquals('2026-03-01T16:00:00.000Z', e.endDate);
        System.assertEquals('Australia/Sydney', e.timezone);
        System.assertEquals(false, e.isArchived);
        System.assertEquals(true, e.published);
        System.assert(mock.requestedEndpoints[0].contains('/v1/events?'), mock.requestedEndpoints[0]);
        System.assert(mock.requestedEndpoints[0].contains('page=1'), mock.requestedEndpoints[0]);
        System.assert(mock.requestedEndpoints[0].contains('pageSize=100'), mock.requestedEndpoints[0]);
    }

    @IsTest
    static void fetchHumanitixEventsReportsTheLastPage() {
        Test.setMock(
            HttpCalloutMock.class,
            new HumanitixCalloutMock().enqueue(200, HumanitixTestDataFactory.pageBody('events', HumanitixTestDataFactory.eventJson(), 101, 2, 100))
        );
        Test.startTest();
        HumanitixSyncSettingsController.EventPageDto result = HumanitixSyncSettingsController.fetchHumanitixEvents(2);
        Test.stopTest();
        System.assertEquals(2, result.page);
        System.assertEquals(false, result.hasNextPage, '2 x 100 >= 101');
    }

    @IsTest
    static void fetchHumanitixEventsExplainsAnAuthFailure() {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(401, '{"message":"Unauthorized"}'));
        String message;
        Test.startTest();
        try {
            HumanitixSyncSettingsController.fetchHumanitixEvents(null);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Test.stopTest();
        System.assertEquals('Humanitix returned HTTP 401. Check the API key on the Connection tab.', message);
    }

    private static String fetchFailureFor(Integer status) {
        Test.setMock(HttpCalloutMock.class, new HumanitixCalloutMock().enqueue(status, '{"message":"x"}'));
        String message;
        Test.startTest();
        try {
            HumanitixSyncSettingsController.fetchHumanitixEvents(null);
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Test.stopTest();
        return message;
    }

    @IsTest
    static void fetchHumanitixEventsExplainsABusyHumanitix() {
        System.assertEquals('Humanitix is busy or unavailable (HTTP 503). Try Refresh in a minute.', fetchFailureFor(503));
    }

    @IsTest
    static void fetchHumanitixEventsKeepsOtherStatusesPlain() {
        System.assertEquals('Humanitix returned HTTP 404.', fetchFailureFor(404));
    }

    @IsTest
    static void calloutFailureMessageExplainsAMissingApiKey() {
        System.assertEquals(
            'Add your Humanitix API key on the Connection tab, then try again.',
            HumanitixSyncSettingsController.calloutFailureMessage('Field HumanitixAPI.ApiKey does not exist. Check spelling.')
        );
        System.assertEquals(
            'Humanitix could not be reached: Read timed out',
            HumanitixSyncSettingsController.calloutFailureMessage('Read timed out')
        );
    }

    private static Map<String, Metadata.CustomMetadata> deployedByFullName() {
        Map<String, Metadata.CustomMetadata> out = new Map<String, Metadata.CustomMetadata>();
        for (Metadata.Metadata md : HumanitixMetadataWriter.lastContainer.getMetadata()) {
            Metadata.CustomMetadata cmt = (Metadata.CustomMetadata) md;
            System.assert(!out.containsKey(cmt.fullName), 'Duplicate record in one deploy: ' + cmt.fullName);
            out.put(cmt.fullName, cmt);
        }
        return out;
    }

    private static Object valueOf(Metadata.CustomMetadata cmt, String field) {
        for (Metadata.CustomMetadataValue v : cmt.values) {
            if (v.field == field) {
                return v.value;
            }
        }
        return null;
    }

    @IsTest
    static void getSyncSettingsReportsTheContactAccountOption() {
        System.assertEquals('None', HumanitixSyncSettingsController.getSyncSettings().contactAccount);
    }

    @IsTest
    static void unchangedContactAccountDeploysOnlyTheSettingsRecord() {
        HumanitixSyncSettingsController.SettingsDto dto = validDto();
        dto.contactAccount = 'None';
        Test.startTest();
        HumanitixSyncSettingsController.saveSyncSettings(JSON.serialize(dto));
        Test.stopTest();
        System.assertEquals(new Set<String>{ 'Humanitix_Sync_Setting.Default' }, deployedByFullName().keySet());
    }

    @IsTest
    static void customContactAccountLeavesTheMappingsAlone() {
        HumanitixSyncSettingsController.SettingsDto dto = validDto();
        dto.contactAccount = 'Custom';
        Test.startTest();
        HumanitixSyncSettingsController.saveSyncSettings(JSON.serialize(dto));
        Test.stopTest();
        System.assertEquals(new Set<String>{ 'Humanitix_Sync_Setting.Default' }, deployedByFullName().keySet());
    }

    @IsTest
    static void switchingToEventAccountDeploysTheMappingsWithTheSettings() {
        HumanitixSyncSettingsController.SettingsDto dto = validDto();
        dto.contactAccount = 'EventAccount';
        Test.startTest();
        HumanitixSyncSettingsController.saveSyncSettings(JSON.serialize(dto));
        Test.stopTest();

        Map<String, Metadata.CustomMetadata> deployed = deployedByFullName();
        System.assertEquals('Sync Settings', HumanitixMetadataWriter.lastPurpose);
        System.assert(deployed.containsKey('Humanitix_Sync_Setting.Default'));
        System.assertEquals(true, valueOf(deployed.get('Humanitix_Object_Mapping.Event_to_Account'), 'Is_Active__c'));
        System.assertEquals(true, valueOf(deployed.get('Humanitix_Field_Mapping.Order_to_Contact_08'), 'Is_Active__c'));
        System.assertEquals('Event', valueOf(deployed.get('Humanitix_Object_Mapping.Event_to_Account'), 'Source_Resource__c'), 'Other values are copied, not cleared');
    }

    @IsTest
    static void validateRejectsAnUnknownContactAccountOption() {
        HumanitixSyncSettingsController.SettingsDto dto = validDto();
        dto.contactAccount = 'Household';
        List<String> problems = HumanitixSyncSettingsController.validate(dto);
        System.assertEquals(1, problems.size(), String.join(problems, ' | '));
        System.assert(problems[0].startsWith('Contact account must be'), problems[0]);
    }

    @IsTest
    static void getSyncSettingsDescribesPersonAccounts() {
        HumanitixSyncSettingsController.SettingsDto dto = HumanitixSyncSettingsController.getSyncSettings();
        System.assertEquals(HumanitixContactAccountService.personAccountsEnabled(), dto.personAccountsEnabled);
        System.assertEquals(HumanitixContactAccountService.personRecordTypes().size(), dto.personRecordTypes.size());
        System.assertEquals(HumanitixContactAccountService.currentPersonRecordTypeId(), dto.personRecordTypeId);
    }

    @IsTest
    static void personAccountWithoutPersonAccountsIsRejectedOnSave() {
        if (HumanitixContactAccountService.personAccountsEnabled()) {
            return;
        }
        HumanitixSyncSettingsController.SettingsDto dto = validDto();
        dto.contactAccount = 'PersonAccount';
        String message;
        try {
            HumanitixSyncSettingsController.saveSyncSettings(JSON.serialize(dto));
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        System.assertEquals('The Contact account change could not be applied: Person Accounts are not enabled in this org.', message);
    }
}
