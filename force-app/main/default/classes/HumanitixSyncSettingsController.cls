/**
 * Backs the Sync Settings tab of the Humanitix Setup console. Reads through
 * HumanitixSyncConfig (so config fallbacks display correctly), saves the
 * `Default` Humanitix Sync Setting record via HumanitixMetadataWriter (async
 * metadata deploy), and flips the Humanitix Sync Toggle kill switch with plain
 * DML (instant).
 *
 * Saves always send the full field set: CMT deploys merge per field, so a
 * cleared input must reach the deploy as an explicit null.
 */
public with sharing class HumanitixSyncSettingsController {
    private static final String RECORD_FULL_NAME = 'Humanitix_Sync_Setting.Default';
    private static final String RECORD_LABEL = 'Default';
    private static final Set<String> SINCE_MODES = new Set<String>{ 'Modified', 'FullPull' };
    public static final Integer MAX_SELECTED_EVENTS = 1000;
    private static final Integer EVENT_PAGE_SIZE = 100;
    private static final Pattern EVENT_ID_PATTERN = Pattern.compile('^[A-Za-z0-9_-]{1,64}$');

    public class SettingsDto {
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public List<String> enabledResources;
        @AuraEnabled public String eventSelection;
        @AuraEnabled public List<String> selectedEventIds;
        @AuraEnabled public String ticketStatusFilter;
        @AuraEnabled public Integer maxRetries;
        @AuraEnabled public Integer retryDelayMinutes;
        @AuraEnabled public String sinceMode;
        @AuraEnabled public String namedCredentialName;
        @AuraEnabled public Boolean recordExists;
        @AuraEnabled public String contactAccount;
    }

    public class EventSummary {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String startDate;
        @AuraEnabled public String endDate;
        @AuraEnabled public String timezone;
        @AuraEnabled public Boolean isArchived;
        @AuraEnabled public Boolean published;
    }

    public class EventPageDto {
        @AuraEnabled public List<EventSummary> events = new List<EventSummary>();
        @AuraEnabled public Boolean hasNextPage = false;
        @AuraEnabled public Integer page;
    }

    @AuraEnabled
    public static SettingsDto getSyncSettings() {
        try {
            SettingsDto dto = new SettingsDto();
            dto.pageSize = HumanitixSyncConfig.pageSize();
            dto.enabledResources = HumanitixSyncConfig.enabledResources();
            dto.eventSelection = HumanitixSyncConfig.eventSelection();
            dto.selectedEventIds = HumanitixSyncConfig.selectedEventIds();
            dto.ticketStatusFilter = HumanitixSyncConfig.ticketStatusFilter();
            dto.maxRetries = HumanitixSyncConfig.maxRetries();
            dto.retryDelayMinutes = HumanitixSyncConfig.retryDelayMinutes();
            dto.sinceMode = HumanitixSyncConfig.sinceMode();
            dto.namedCredentialName = HumanitixSyncConfig.namedCredentialName();
            dto.recordExists = Humanitix_Sync_Setting__mdt.getInstance('Default') != null;
            dto.contactAccount = HumanitixContactAccountService.currentMode();
            return dto;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** Validates and deploys the settings record; returns the deploy job id (null in tests). */
    @AuraEnabled
    public static String saveSyncSettings(String settingsJson) {
        SettingsDto dto;
        try {
            dto = (SettingsDto) JSON.deserialize(settingsJson, SettingsDto.class);
        } catch (Exception e) {
            throw new AuraHandledException('The settings payload could not be read: ' + e.getMessage());
        }
        List<String> problems = validate(dto);
        if (!problems.isEmpty()) {
            throw new AuraHandledException(String.join(problems, ' '));
        }
        Map<String, Object> values = new Map<String, Object>{
            'Page_Size__c' => dto.pageSize,
            'Enabled_Resources__c' => String.join(dto.enabledResources, ','),
            'In_Future_Only__c' => dto.eventSelection == HumanitixSyncConfig.SELECTION_FUTURE_ONLY,
            'Event_Selection__c' => dto.eventSelection,
            'Selected_Event_Ids__c' => selectedIdsValue(dto.selectedEventIds),
            'Ticket_Status_Filter__c' => String.isBlank(dto.ticketStatusFilter) ? null : dto.ticketStatusFilter.trim(),
            'Max_Retries__c' => dto.maxRetries,
            'Retry_Delay_Minutes__c' => dto.retryDelayMinutes,
            'Since_Mode__c' => dto.sinceMode,
            'Named_Credential_Name__c' => String.isBlank(dto.namedCredentialName) ? null : dto.namedCredentialName.trim()
        };
        Map<String, Metadata.CustomMetadata> byFullName = new Map<String, Metadata.CustomMetadata>();
        try {
            for (Metadata.CustomMetadata r : contactAccountRecords(dto)) {
                byFullName.put(r.fullName, r);
            }
        } catch (HumanitixMappingException e) {
            throw auraError('The Contact account change could not be applied: ' + e.getMessage());
        }
        // Put last so the edited settings win over a missing-default copy of the same record.
        byFullName.put(RECORD_FULL_NAME, HumanitixMetadataWriter.record(RECORD_FULL_NAME, RECORD_LABEL, values));
        try {
            return HumanitixMetadataWriter.deploy(byFullName.values(), 'Sync Settings');
        } catch (Exception e) {
            throw new AuraHandledException('The settings deployment could not be started: ' + e.getMessage());
        }
    }

    /** Mapping records that put the org in the chosen Contact account option; none when unchanged or Custom. */
    private static List<Metadata.CustomMetadata> contactAccountRecords(SettingsDto dto) {
        if (String.isBlank(dto.contactAccount) || dto.contactAccount == HumanitixContactAccountService.MODE_CUSTOM) {
            return new List<Metadata.CustomMetadata>();
        }
        HumanitixMappingAdminController.PendingChanges pending = HumanitixContactAccountService.changesFor(dto.contactAccount);
        if (pending.objectMappings.isEmpty() && pending.fieldMappings.isEmpty()) {
            return new List<Metadata.CustomMetadata>();
        }
        return HumanitixMappingAdminController.deployRecordsFor(pending);
    }

    @TestVisible
    private static List<String> validate(SettingsDto dto) {
        List<String> problems = new List<String>();
        if (dto.pageSize == null || dto.pageSize < 1 || dto.pageSize > 1000) {
            problems.add('Page Size must be between 1 and 1000.');
        }
        if (dto.enabledResources == null || dto.enabledResources.isEmpty()) {
            problems.add('Enable at least one resource.');
        } else {
            for (String r : dto.enabledResources) {
                if (!HumanitixSyncConfig.CANONICAL_ORDER.contains(r)) {
                    problems.add('Unknown resource: ' + r + '.');
                }
            }
        }
        if (dto.maxRetries == null || dto.maxRetries < 0 || dto.maxRetries > 10) {
            problems.add('Max Retries must be between 0 and 10.');
        }
        if (dto.retryDelayMinutes == null || dto.retryDelayMinutes < 1 || dto.retryDelayMinutes > 1440) {
            problems.add('Retry Delay must be between 1 and 1440 minutes.');
        }
        if (!SINCE_MODES.contains(dto.sinceMode)) {
            problems.add('Since Mode must be Modified or FullPull.');
        }
        if (dto.eventSelection == null || !HumanitixSyncConfig.EVENT_SELECTIONS.contains(dto.eventSelection)) {
            problems.add('Sync Events must be All, FutureOnly or Selected.');
        }
        Set<String> uniqueIds = new Set<String>();
        if (dto.selectedEventIds != null) {
            for (String raw : dto.selectedEventIds) {
                if (String.isBlank(raw)) {
                    continue;
                }
                String id = raw.trim();
                if (!EVENT_ID_PATTERN.matcher(id).matches()) {
                    problems.add('"' + id.abbreviate(70) + '" is not a valid Humanitix event id.');
                    break;
                }
                uniqueIds.add(id);
            }
        }
        if (uniqueIds.size() > MAX_SELECTED_EVENTS) {
            problems.add('Select at most ' + MAX_SELECTED_EVENTS + ' events.');
        }
        if (dto.eventSelection == HumanitixSyncConfig.SELECTION_SELECTED && uniqueIds.isEmpty()) {
            problems.add('Select at least one event, or choose All events.');
        }
        if (String.isNotBlank(dto.contactAccount) && !HumanitixContactAccountService.ALL_MODES.contains(dto.contactAccount)) {
            problems.add('Contact account must be None, EventAccount or PersonAccount.');
        }
        return problems;
    }

    /** Comma-joined, trimmed, de-duplicated ids; null when there are none (CMT merge needs the explicit null). */
    private static String selectedIdsValue(List<String> ids) {
        List<String> parsed = HumanitixSyncConfig.parseIds(ids == null ? null : String.join(ids, ','));
        return parsed.isEmpty() ? null : String.join(parsed, ',');
    }

    /**
     * One page of the org's Humanitix events for the Sync Settings event picker.
     * Live on purpose (not cacheable): the list must reflect Humanitix now.
     */
    @AuraEnabled
    public static EventPageDto fetchHumanitixEvents(Integer page) {
        Integer p = (page == null || page < 1) ? 1 : page;
        String path = '/v1/events' + HumanitixHttpClient.buildQuery(new Map<String, String>{
            'page' => String.valueOf(p),
            'pageSize' => String.valueOf(EVENT_PAGE_SIZE)
        });
        HttpResponse res;
        try {
            res = new HumanitixHttpClient(HumanitixSyncConfig.namedCredentialName()).get(path);
        } catch (Exception e) {
            throw auraError('Humanitix could not be reached: ' + e.getMessage());
        }
        Integer status = res.getStatusCode();
        if (status < 200 || status > 299) {
            throw auraError('Humanitix returned HTTP ' + status + '. Check the API key on the Connection tab.');
        }
        HumanitixApiResponse api = HumanitixApiResponse.parse(res.getBody(), 'events', status);
        EventPageDto out = new EventPageDto();
        out.page = p;
        out.hasNextPage = api.hasNextPage();
        for (Object o : api.records) {
            if (!(o instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> raw = (Map<String, Object>) o;
            EventSummary e = new EventSummary();
            e.id = textOf(raw.get('_id'));
            e.name = textOf(raw.get('name'));
            e.startDate = textOf(raw.get('startDate'));
            e.endDate = textOf(raw.get('endDate'));
            e.timezone = textOf(raw.get('timezone'));
            e.isArchived = raw.get('isArchived') == true;
            e.published = raw.get('published') != false;
            if (String.isNotBlank(e.id)) {
                out.events.add(e);
            }
        }
        return out;
    }

    private static String textOf(Object o) {
        return o == null ? null : String.valueOf(o);
    }

    /** AuraHandledException whose getMessage() is the real text (tests and logs see it too). */
    private static AuraHandledException auraError(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    @AuraEnabled
    public static Boolean getSyncEnabled() {
        return HumanitixSyncConfig.syncEnabled();
    }

    /** Kill switch: plain DML on the org-default custom setting row, effective immediately. */
    @AuraEnabled
    public static void setSyncEnabled(Boolean enabled) {
        if (enabled == null) {
            throw new AuraHandledException('A value for enabled is required.');
        }
        try {
            Humanitix_Sync_Toggle__c toggle = Humanitix_Sync_Toggle__c.getOrgDefaults();
            if (toggle == null || toggle.Id == null) {
                toggle = new Humanitix_Sync_Toggle__c(SetupOwnerId = UserInfo.getOrganizationId());
            }
            toggle.Sync_Enabled__c = enabled;
            upsert toggle;
        } catch (Exception e) {
            throw new AuraHandledException('The sync toggle could not be saved: ' + e.getMessage());
        }
    }
}
