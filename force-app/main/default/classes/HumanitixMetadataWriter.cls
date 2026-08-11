/**
 * Shared runtime writer for the connector's Custom Metadata records (sync
 * settings, mappings). Metadata API deploys of CMT records are broken on the
 * platform (Summer '26), so all writes go through
 * Metadata.Operations.enqueueDeployment, which is asynchronous: the deploy is
 * tracked in Humanitix_Metadata_Deploy__c so the Setup UI can poll for the
 * outcome (Apex has no deploy-status API).
 *
 * Unlike HumanitixMappingSeeder.containerFor (which skips nulls because it only
 * seeds defaults), record() keeps null values: CMT deploys merge per field, so
 * clearing a field requires sending it explicitly.
 *
 * enqueueDeployment is not permitted in test context; deploy() captures the
 * container in @TestVisible seams and returns null under tests (the
 * HumanitixMappingSeeder pattern).
 */
public with sharing class HumanitixMetadataWriter {
    @TestVisible private static Metadata.DeployContainer lastContainer;
    @TestVisible private static String lastPurpose;

    /** Build one CustomMetadata record from a full field map (nulls included). */
    public static Metadata.CustomMetadata record(String fullName, String label, Map<String, Object> values) {
        Metadata.CustomMetadata cmt = new Metadata.CustomMetadata();
        cmt.fullName = fullName;
        cmt.label = label;
        for (String field : values.keySet()) {
            Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
            v.field = field;
            v.value = values.get(field);
            cmt.values.add(v);
        }
        return cmt;
    }

    /**
     * Enqueue an async deployment of the given records and insert a Pending
     * ledger row keyed by the deploy job id. Returns the job id (null in tests).
     */
    public static Id deploy(List<Metadata.CustomMetadata> records, String purpose) {
        Metadata.DeployContainer container = new Metadata.DeployContainer();
        for (Metadata.CustomMetadata r : records) {
            container.addMetadata(r);
        }
        lastContainer = container;
        lastPurpose = purpose;
        if (Test.isRunningTest()) {
            return null; // enqueueDeployment is not permitted in test context
        }
        Id jobId = Metadata.Operations.enqueueDeployment(container, new StatusCallback());
        insert new Humanitix_Metadata_Deploy__c(
            Deploy_Job_Id__c = String.valueOf(jobId),
            Status__c = 'Pending',
            Purpose__c = purpose
        );
        return jobId;
    }

    /** Polled by the Setup UI after a save. Returns null while the ledger row is not yet visible. */
    @AuraEnabled
    public static Humanitix_Metadata_Deploy__c getDeployStatus(String deployJobId) {
        if (String.isBlank(deployJobId)) {
            return null;
        }
        List<Humanitix_Metadata_Deploy__c> rows = [
            SELECT Id, Deploy_Job_Id__c, Status__c, Purpose__c, Error_Detail__c, Completed_At__c
            FROM Humanitix_Metadata_Deploy__c
            WHERE Deploy_Job_Id__c = :deployJobId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /** Runs in its own async context when the deployment finishes; DML is permitted there. */
    public class StatusCallback implements Metadata.DeployCallback {
        public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext ctx) {
            Id jobId = ctx == null ? null : ctx.getCallbackJobId();
            if (jobId == null) {
                return;
            }
            Boolean ok = result != null && result.status == Metadata.DeployStatus.SUCCEEDED;
            String detail = '';
            if (!ok && result != null && result.details != null && result.details.componentFailures != null) {
                for (Metadata.DeployMessage m : result.details.componentFailures) {
                    detail += m.fullName + ': ' + m.problem + '; ';
                }
            }
            if (!ok && String.isBlank(detail) && result != null) {
                detail = 'Deployment status: ' + String.valueOf(result.status);
            }
            upsertStatus(String.valueOf(jobId), ok ? 'Succeeded' : 'Failed', detail);
        }
    }

    @TestVisible
    private static void upsertStatus(String jobId, String status, String detail) {
        Humanitix_Metadata_Deploy__c row = new Humanitix_Metadata_Deploy__c(
            Deploy_Job_Id__c = jobId,
            Status__c = status,
            Error_Detail__c = String.isBlank(detail) ? null : detail.abbreviate(32768),
            Completed_At__c = Datetime.now()
        );
        upsert row Humanitix_Metadata_Deploy__c.Deploy_Job_Id__c;
    }
}
