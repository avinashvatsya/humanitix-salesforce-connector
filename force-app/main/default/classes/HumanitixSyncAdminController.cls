/**
 * Apex controller for the "Run Sync Now" admin Lightning Web Component: kicks off a
 * manual run, reads recent run history, and self-heals missing default mappings.
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

    /**
     * Called every time the admin panel loads. Unlocked packages don't support
     * post-install scripts, so seeding happens here instead: whenever a shipped
     * default mapping record is missing from the org (a fresh install, or an
     * upgrade that ships new defaults), enqueue the seeder that deploys the
     * missing records. Returns true when seeding is needed so the UI can tell
     * the admin the defaults are being installed.
     */
    @AuraEnabled
    public static Boolean ensureDefaultMappings() {
        try {
            // Fresh installs AND upgrades that ship new defaults both land here;
            // the seeder deploys only missing records, so edits are never touched.
            if (HumanitixMappingSeeder.missingDefaults().isEmpty()) {
                return false;
            }
            Integer inFlight = [
                SELECT COUNT()
                FROM AsyncApexJob
                WHERE ApexClass.Name = 'HumanitixMappingSeeder'
                    AND JobType = 'Queueable'
                    AND Status IN ('Queued', 'Preparing', 'Processing')
            ];
            if (inFlight == 0) {
                System.enqueueJob(new HumanitixMappingSeeder());
            }
            return true;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** The Dashboard "Ready to sync" checklist. Not cacheable: it includes a live connection check. */
    @AuraEnabled
    public static List<HumanitixReadinessService.Item> getReadiness() {
        try {
            return HumanitixReadinessService.check();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Humanitix_Sync_Log__c> getRecentRuns() {
        return [
            SELECT Id, Name, Status__c, Trigger_Source__c, Started_At__c, Finished_At__c,
                Total_Records_Processed__c, Total_Records_Failed__c, Total_Errors__c, Error_Summary__c
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
