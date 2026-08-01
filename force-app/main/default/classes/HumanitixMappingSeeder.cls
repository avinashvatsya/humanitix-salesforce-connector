/**
 * Seeds the connector's default CustomMetadata records (object/field mappings +
 * the Default sync setting) from the Humanitix_Default_Mappings static resource
 * via Metadata.Operations.enqueueDeployment.
 *
 * Why not ship the records in the package? A Summer '26 platform bug fails any
 * Metadata API deploy that contains CustomMetadata records (UNKNOWN_EXCEPTION,
 * no component failures), which broke package version creation. Apex metadata
 * deployments are unaffected, so the package seeds its defaults from Apex
 * instead. Unlocked packages don't support post-install scripts, so the
 * trigger is HumanitixSyncAdminController.ensureDefaultMappings(), which
 * enqueues this Queueable the first time the Humanitix Setup tab loads in an
 * org with no mapping records.
 *
 * Only records whose DeveloperName does not already exist are deployed, so
 * re-runs and package upgrades never overwrite an admin's edited mappings.
 * (To disable a default mapping, uncheck Is Active rather than deleting it —
 * a deleted record is treated as missing and re-seeded on the next upgrade.)
 *
 * Manual (re-)seed from Developer Console / anonymous Apex:
 *   System.enqueueJob(new HumanitixMappingSeeder());
 */
public with sharing class HumanitixMappingSeeder implements Queueable {
    public void execute(QueueableContext ctx) {
        seedMissing();
    }

    /**
     * Enqueues one metadata deployment for every default record missing from
     * this org. Returns the async deployment job id, or null when the org
     * already has every default (or in tests, where Metadata.Operations is not
     * allowed to enqueue).
     */
    public static Id seedMissing() {
        List<HumanitixDefaultMappings.DefaultRecord> missing = missingRecords(existingFullNames());
        if (missing.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'Humanitix seeder: all default mapping records already exist; nothing to deploy.');
            return null;
        }
        Metadata.DeployContainer container = containerFor(missing);
        System.debug(LoggingLevel.INFO, 'Humanitix seeder: deploying ' + missing.size() + ' default mapping record(s).');
        if (Test.isRunningTest()) {
            return null; // enqueueDeployment is not permitted in test context
        }
        return Metadata.Operations.enqueueDeployment(container, new Callback());
    }

    /** DeveloperNames (as Type.DeveloperName) already present in this org. */
    @TestVisible
    private static Set<String> existingFullNames() {
        Set<String> typeNames = new Set<String>();
        for (HumanitixDefaultMappings.DefaultRecord r : HumanitixDefaultMappings.records()) {
            typeNames.add(r.typeName);
        }
        Set<String> existing = new Set<String>();
        for (String typeName : typeNames) {
            String obj = HumanitixMappingConfig.safeIdentifier(typeName + '__mdt');
            for (SObject rec : Database.query('SELECT DeveloperName FROM ' + obj)) {
                existing.add(typeName + '.' + (String) rec.get('DeveloperName'));
            }
        }
        return existing;
    }

    @TestVisible
    private static List<HumanitixDefaultMappings.DefaultRecord> missingRecords(Set<String> existing) {
        List<HumanitixDefaultMappings.DefaultRecord> out = new List<HumanitixDefaultMappings.DefaultRecord>();
        for (HumanitixDefaultMappings.DefaultRecord r : HumanitixDefaultMappings.records()) {
            if (!existing.contains(r.fullName())) {
                out.add(r);
            }
        }
        return out;
    }

    @TestVisible
    private static Metadata.DeployContainer containerFor(List<HumanitixDefaultMappings.DefaultRecord> records) {
        Metadata.DeployContainer container = new Metadata.DeployContainer();
        for (HumanitixDefaultMappings.DefaultRecord r : records) {
            Metadata.CustomMetadata cmt = new Metadata.CustomMetadata();
            cmt.fullName = r.fullName();
            cmt.label = r.label;
            for (String field : r.values.keySet()) {
                Object raw = r.values.get(field);
                if (raw == null) {
                    continue;
                }
                Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
                v.field = field;
                v.value = raw;
                cmt.values.add(v);
            }
            container.addMetadata(cmt);
        }
        return container;
    }

    /** Surfaces the async deployment outcome in debug logs / Setup > Deployment Status. */
    public class Callback implements Metadata.DeployCallback {
        public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext ctx) {
            if (result != null && result.status == Metadata.DeployStatus.SUCCEEDED) {
                System.debug(LoggingLevel.INFO, 'Humanitix seeder: default mapping records deployed successfully.');
                return;
            }
            String detail = '';
            if (result != null && result.details != null && result.details.componentFailures != null) {
                for (Metadata.DeployMessage m : result.details.componentFailures) {
                    detail += m.fullName + ': ' + m.problem + '; ';
                }
            }
            System.debug(
                LoggingLevel.ERROR,
                'Humanitix seeder: metadata deployment did not succeed (status=' +
                    (result == null ? 'null' : String.valueOf(result.status)) + '). ' + detail +
                    'Re-run with: System.enqueueJob(new HumanitixMappingSeeder());'
            );
        }
    }
}
