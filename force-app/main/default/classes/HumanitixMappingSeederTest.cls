/**
 * Tests the install-time seeder that deploys default mapping CMT records via
 * Metadata.Operations. The enqueueDeployment call itself is not allowed in
 * test context, so the tests cover the deterministic parts: which records are
 * considered missing, the deploy container built for them, and the callback's
 * result handling.
 */
@IsTest
private class HumanitixMappingSeederTest {
    @IsTest
    static void missingRecordsIsAllWhenOrgHasNone() {
        List<HumanitixDefaultMappings.DefaultRecord> missing =
            HumanitixMappingSeeder.missingRecords(new Set<String>());
        System.assertEquals(HumanitixDefaultMappings.records().size(), missing.size());
    }

    @IsTest
    static void missingRecordsIsEmptyWhenAllExist() {
        Set<String> existing = new Set<String>();
        for (HumanitixDefaultMappings.DefaultRecord r : HumanitixDefaultMappings.records()) {
            existing.add(r.fullName());
        }
        System.assertEquals(0, HumanitixMappingSeeder.missingRecords(existing).size());
    }

    @IsTest
    static void containerCarriesEveryRecordWithValues() {
        List<HumanitixDefaultMappings.DefaultRecord> all = HumanitixDefaultMappings.records();
        Metadata.DeployContainer container = HumanitixMappingSeeder.containerFor(all);
        System.assertEquals(all.size(), container.getMetadata().size());

        Metadata.CustomMetadata eventToCampaign;
        for (Metadata.Metadata m : container.getMetadata()) {
            Metadata.CustomMetadata c = (Metadata.CustomMetadata) m;
            if (c.fullName == 'Humanitix_Object_Mapping.Event_to_Campaign') {
                eventToCampaign = c;
            }
        }
        System.assertNotEquals(null, eventToCampaign, 'container must include Event_to_Campaign');
        System.assertEquals('Event to Campaign', eventToCampaign.label);
        Map<String, Object> vals = new Map<String, Object>();
        for (Metadata.CustomMetadataValue v : eventToCampaign.values) {
            vals.put(v.field, v.value);
        }
        System.assertEquals('Campaign', vals.get('Target_SObject__c'));
        System.assertEquals('Event', vals.get('Source_Resource__c'));
        System.assertEquals(true, vals.get('Is_Active__c'));
    }

    @IsTest
    static void existingFullNamesQueriesEveryShippedType() {
        // The org may or may not have seeded records (scratch org vs package
        // build org); the invariant is that the query path works and only ever
        // returns full names of shipped types.
        Set<String> existing = HumanitixMappingSeeder.existingFullNames();
        for (String fullName : existing) {
            System.assert(
                fullName.startsWith('Humanitix_Object_Mapping.') ||
                fullName.startsWith('Humanitix_Field_Mapping.') ||
                fullName.startsWith('Humanitix_Sync_Setting.'),
                'unexpected type in existing records: ' + fullName
            );
        }
    }

    @IsTest
    static void queueableRunsWithoutDeployingInTests() {
        Test.startTest();
        System.enqueueJob(new HumanitixMappingSeeder());
        Test.stopTest();
        // seedMissing() stops short of enqueueDeployment in test context; the
        // assertion is that the job completed without throwing.
        System.assertEquals(
            1,
            [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'HumanitixMappingSeeder']
        );
    }

    @IsTest
    static void callbackHandlesSuccessAndFailure() {
        Metadata.DeployResult ok = new Metadata.DeployResult();
        ok.status = Metadata.DeployStatus.SUCCEEDED;

        Metadata.DeployMessage msg = new Metadata.DeployMessage();
        msg.fullName = 'Humanitix_Object_Mapping.Event_to_Campaign';
        msg.problem = 'boom';
        Metadata.DeployDetails details = new Metadata.DeployDetails();
        details.componentFailures = new List<Metadata.DeployMessage>{ msg };
        Metadata.DeployResult bad = new Metadata.DeployResult();
        bad.status = Metadata.DeployStatus.FAILED;
        bad.details = details;

        HumanitixMappingSeeder.Callback cb = new HumanitixMappingSeeder.Callback();
        cb.handleResult(ok, null);
        cb.handleResult(bad, null);
        cb.handleResult(null, null);
        // The callback only logs; reaching here without an exception on all
        // three shapes (success, failure with details, null) is the contract.
        System.assert(true);
    }
}
