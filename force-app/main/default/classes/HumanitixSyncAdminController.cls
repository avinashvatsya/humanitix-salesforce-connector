/**
 * Apex controller for the "Run Sync Now" admin Lightning Web Component: kicks off a
 * manual run and reads recent run history.
 */
public with sharing class HumanitixSyncAdminController {
    @AuraEnabled
    public static Id runSyncNow() {
        try {
            return HumanitixSyncLauncher.start('Manual');
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Humanitix_Sync_Log__c> getRecentRuns() {
        return [
            SELECT Id, Name, Status__c, Trigger_Source__c, Started_At__c, Finished_At__c,
                Total_Records_Processed__c, Total_Records_Failed__c, Total_Errors__c
            FROM Humanitix_Sync_Log__c
            ORDER BY Started_At__c DESC NULLS LAST
            LIMIT 25
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Boolean isSyncEnabled() {
        return HumanitixSyncConfig.syncEnabled();
    }
}
