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

    public class SettingsDto {
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public List<String> enabledResources;
        @AuraEnabled public Boolean inFutureOnly;
        @AuraEnabled public String ticketStatusFilter;
        @AuraEnabled public Integer maxRetries;
        @AuraEnabled public Integer retryDelayMinutes;
        @AuraEnabled public String sinceMode;
        @AuraEnabled public String namedCredentialName;
        @AuraEnabled public Boolean recordExists;
    }

    @AuraEnabled
    public static SettingsDto getSyncSettings() {
        try {
            SettingsDto dto = new SettingsDto();
            dto.pageSize = HumanitixSyncConfig.pageSize();
            dto.enabledResources = HumanitixSyncConfig.enabledResources();
            dto.inFutureOnly = HumanitixSyncConfig.inFutureOnly();
            dto.ticketStatusFilter = HumanitixSyncConfig.ticketStatusFilter();
            dto.maxRetries = HumanitixSyncConfig.maxRetries();
            dto.retryDelayMinutes = HumanitixSyncConfig.retryDelayMinutes();
            dto.sinceMode = HumanitixSyncConfig.sinceMode();
            dto.namedCredentialName = HumanitixSyncConfig.namedCredentialName();
            dto.recordExists = Humanitix_Sync_Setting__mdt.getInstance('Default') != null;
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
            'In_Future_Only__c' => dto.inFutureOnly == true,
            'Ticket_Status_Filter__c' => String.isBlank(dto.ticketStatusFilter) ? null : dto.ticketStatusFilter.trim(),
            'Max_Retries__c' => dto.maxRetries,
            'Retry_Delay_Minutes__c' => dto.retryDelayMinutes,
            'Since_Mode__c' => dto.sinceMode,
            'Named_Credential_Name__c' => String.isBlank(dto.namedCredentialName) ? null : dto.namedCredentialName.trim()
        };
        try {
            return HumanitixMetadataWriter.deploy(
                new List<Metadata.CustomMetadata>{
                    HumanitixMetadataWriter.record(RECORD_FULL_NAME, RECORD_LABEL, values)
                },
                'Sync Settings'
            );
        } catch (Exception e) {
            throw new AuraHandledException('The settings deployment could not be started: ' + e.getMessage());
        }
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
        return problems;
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
