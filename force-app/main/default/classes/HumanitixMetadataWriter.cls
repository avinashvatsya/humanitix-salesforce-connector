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
     * Enqueue an async deployment of the given records. Returns a tracking
     * token (null in tests) the UI polls getDeployStatus with.
     *
     * Two platform constraints shape this: enqueueDeployment creates a
     * DeployRequest (a setup object), so writing the ledger row in this
     * transaction would be MIXED_DML; and the id enqueueDeployment returns
     * (DeployRequest, 0Af) is not the id the callback sees from
     * getCallbackJobId() (AsyncApexJob, 707). So the ledger key is a token we
     * generate here and serialize into the callback, which writes the row in
     * its own transaction; until then a missing row means Pending.
     */
    public static String deploy(List<Metadata.CustomMetadata> records, String purpose) {
        Metadata.DeployContainer container = new Metadata.DeployContainer();
        for (Metadata.CustomMetadata r : records) {
            container.addMetadata(r);
        }
        lastContainer = container;
        lastPurpose = purpose;
        if (Test.isRunningTest()) {
            return null; // enqueueDeployment is not permitted in test context
        }
        String token = 'MDD-' + String.valueOf(Datetime.now().getTime()) + '-' +
            String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Metadata.Operations.enqueueDeployment(container, new StatusCallback(token, purpose));
        return token;
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

    /** Runs in its own async transaction when the deployment finishes; DML is permitted there. */
    public class StatusCallback implements Metadata.DeployCallback {
        private String deployToken;
        private String purpose;

        public StatusCallback(String deployToken, String purpose) {
            this.deployToken = deployToken;
            this.purpose = purpose;
        }

        public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext ctx) {
            if (String.isBlank(deployToken)) {
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
            upsertStatus(deployToken, ok ? 'Succeeded' : 'Failed', purpose, detail);
        }
    }

    @TestVisible
    private static void upsertStatus(String jobId, String status, String purpose, String detail) {
        Humanitix_Metadata_Deploy__c row = new Humanitix_Metadata_Deploy__c(
            Deploy_Job_Id__c = jobId,
            Status__c = status,
            Purpose__c = purpose,
            Error_Detail__c = String.isBlank(detail) ? null : detail.abbreviate(32768),
            Completed_At__c = Datetime.now()
        );
        upsert row Humanitix_Metadata_Deploy__c.Deploy_Job_Id__c;
    }
}
