@IsTest
private class HumanitixMetadataWriterTest {
    private static final String JOB_ID = '0Af000000000001AAA';

    @IsTest
    static void recordKeepsNullValuesSoClearsDeploy() {
        Metadata.CustomMetadata cmt = HumanitixMetadataWriter.record(
            'Humanitix_Sync_Setting.Default',
            'Default',
            new Map<String, Object>{ 'Page_Size__c' => 50, 'Ticket_Status_Filter__c' => null }
        );
        System.assertEquals('Humanitix_Sync_Setting.Default', cmt.fullName);
        System.assertEquals(2, cmt.values.size(), 'Null values must be included so field clears deploy');
        Map<String, Object> byField = new Map<String, Object>();
        for (Metadata.CustomMetadataValue v : cmt.values) {
            byField.put(v.field, v.value);
        }
        System.assert(byField.containsKey('Ticket_Status_Filter__c'));
        System.assertEquals(null, byField.get('Ticket_Status_Filter__c'));
    }

    @IsTest
    static void deployCapturesContainerInTestContext() {
        Metadata.CustomMetadata cmt = HumanitixMetadataWriter.record(
            'Humanitix_Sync_Setting.Default',
            'Default',
            new Map<String, Object>{ 'Page_Size__c' => 25 }
        );

        Test.startTest();
        String deployToken = HumanitixMetadataWriter.deploy(new List<Metadata.CustomMetadata>{ cmt }, 'Sync Settings');
        Test.stopTest();

        System.assertEquals(null, deployToken, 'enqueueDeployment is not permitted in tests');
        System.assertEquals('Sync Settings', HumanitixMetadataWriter.lastPurpose);
        System.assertEquals(1, HumanitixMetadataWriter.lastContainer.getMetadata().size());
    }

    @IsTest
    static void callbackWritesRowKeyedByToken() {
        Metadata.DeployResult ok = new Metadata.DeployResult();
        ok.status = Metadata.DeployStatus.SUCCEEDED;

        new HumanitixMetadataWriter.StatusCallback(JOB_ID, 'Sync Settings').handleResult(ok, null);

        Humanitix_Metadata_Deploy__c row = HumanitixMetadataWriter.getDeployStatus(JOB_ID);
        System.assertNotEquals(null, row, 'Callback must write the ledger row keyed by the token');
        System.assertEquals('Succeeded', row.Status__c);
        System.assertEquals('Sync Settings', row.Purpose__c);
    }

    @IsTest
    static void callbackWithBlankTokenDoesNothing() {
        Metadata.DeployResult ok = new Metadata.DeployResult();
        ok.status = Metadata.DeployStatus.SUCCEEDED;

        new HumanitixMetadataWriter.StatusCallback(null, 'Sync Settings').handleResult(ok, null);
        new HumanitixMetadataWriter.StatusCallback('', 'Sync Settings').handleResult(null, null);

        System.assertEquals(0, [SELECT COUNT() FROM Humanitix_Metadata_Deploy__c]);
    }

    @IsTest
    static void upsertStatusInsertsThenUpdatesTheSameRow() {
        HumanitixMetadataWriter.upsertStatus(JOB_ID, 'Succeeded', 'Sync Settings', null);
        HumanitixMetadataWriter.upsertStatus(JOB_ID, 'Failed', 'Sync Settings', 'Humanitix_Sync_Setting.Default: boom;');

        List<Humanitix_Metadata_Deploy__c> rows = [
            SELECT Status__c, Purpose__c, Error_Detail__c, Completed_At__c
            FROM Humanitix_Metadata_Deploy__c
            WHERE Deploy_Job_Id__c = :JOB_ID
        ];
        System.assertEquals(1, rows.size(), 'Upsert must key on Deploy_Job_Id__c');
        System.assertEquals('Failed', rows[0].Status__c);
        System.assertEquals('Sync Settings', rows[0].Purpose__c);
        System.assert(rows[0].Error_Detail__c.contains('boom'));
        System.assertNotEquals(null, rows[0].Completed_At__c);
    }

    @IsTest
    static void getDeployStatusReturnsRowOrNull() {
        System.assertEquals(null, HumanitixMetadataWriter.getDeployStatus(null));
        System.assertEquals(null, HumanitixMetadataWriter.getDeployStatus('missing'));

        HumanitixMetadataWriter.upsertStatus(JOB_ID, 'Succeeded', 'Mappings', null);
        Humanitix_Metadata_Deploy__c row = HumanitixMetadataWriter.getDeployStatus(JOB_ID);
        System.assertNotEquals(null, row);
        System.assertEquals('Succeeded', row.Status__c);
    }
}
