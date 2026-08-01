/**
 * Guards the integrity of the packaged Humanitix_Default_Mappings static
 * resource: it must parse, reference only real mapping parents, and produce a
 * config that validates cleanly against the org schema — the same checks the
 * engine performs at runtime, so a bad regeneration of the resource fails the
 * build instead of a subscriber org.
 */
@IsTest
private class HumanitixDefaultMappingsTest {
    @IsTest
    static void resourceParsesWithExpectedShape() {
        List<HumanitixDefaultMappings.DefaultRecord> all = HumanitixDefaultMappings.records();
        Integer objects = 0;
        Integer fields = 0;
        Integer settings = 0;
        Set<String> fullNames = new Set<String>();
        for (HumanitixDefaultMappings.DefaultRecord r : all) {
            System.assert(String.isNotBlank(r.developerName), 'every record needs a developerName');
            System.assert(String.isNotBlank(r.label), 'every record needs a label: ' + r.fullName());
            System.assert(fullNames.add(r.fullName()), 'duplicate default record: ' + r.fullName());
            if (r.typeName == 'Humanitix_Object_Mapping') {
                objects++;
            } else if (r.typeName == 'Humanitix_Field_Mapping') {
                fields++;
            } else if (r.typeName == 'Humanitix_Sync_Setting') {
                settings++;
            } else {
                System.assert(false, 'unexpected default record type: ' + r.typeName);
            }
        }
        System.assert(objects >= 10, 'expected the full set of object mappings, got ' + objects);
        System.assert(fields >= 100, 'expected the full set of field mappings, got ' + fields);
        System.assertEquals(1, settings, 'exactly one default sync setting should ship');
        System.assert(fullNames.contains('Humanitix_Sync_Setting.Default'), 'the sync setting must be the Default record');
    }

    @IsTest
    static void typedBuildersMatchRecordCounts() {
        Integer objects = 0;
        Integer fields = 0;
        for (HumanitixDefaultMappings.DefaultRecord r : HumanitixDefaultMappings.records()) {
            if (r.typeName == 'Humanitix_Object_Mapping') {
                objects++;
            }
            if (r.typeName == 'Humanitix_Field_Mapping') {
                fields++;
            }
        }
        List<Humanitix_Object_Mapping__mdt> oms = HumanitixDefaultMappings.objectMappings();
        List<Humanitix_Field_Mapping__mdt> fms = HumanitixDefaultMappings.fieldMappings();
        System.assertEquals(objects, oms.size());
        System.assertEquals(fields, fms.size());

        // spot-check typed values survive the JSON round trip
        Humanitix_Object_Mapping__mdt eventToCampaign;
        for (Humanitix_Object_Mapping__mdt om : oms) {
            if (om.DeveloperName == 'Event_to_Campaign') {
                eventToCampaign = om;
            }
        }
        System.assertNotEquals(null, eventToCampaign, 'Event_to_Campaign default must ship');
        System.assertEquals('Campaign', eventToCampaign.Target_SObject__c);
        System.assertEquals(true, eventToCampaign.Is_Active__c);
        System.assertNotEquals(null, eventToCampaign.Load_Order__c, 'numeric values must coerce to Decimal');
    }

    @IsTest
    static void everyFieldMappingReferencesAShippedObjectMapping() {
        Set<String> objectNames = new Set<String>();
        for (Humanitix_Object_Mapping__mdt om : HumanitixDefaultMappings.objectMappings()) {
            objectNames.add(om.DeveloperName);
        }
        for (Humanitix_Field_Mapping__mdt fm : HumanitixDefaultMappings.fieldMappings()) {
            System.assert(
                objectNames.contains(fm.Object_Mapping__c),
                'field mapping references unknown parent "' + fm.Object_Mapping__c + '"'
            );
        }
    }

    @IsTest
    static void shippedDefaultsValidateAgainstOrgSchema() {
        HumanitixMappingConfig cfg = HumanitixMappingConfig.fromRecords(
            HumanitixDefaultMappings.objectMappings(),
            HumanitixDefaultMappings.fieldMappings()
        );
        List<String> errors = cfg.validate();
        System.assert(errors.isEmpty(), 'shipped default mappings must validate cleanly; got: ' + errors);
    }
}
