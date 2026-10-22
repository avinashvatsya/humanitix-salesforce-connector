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

    @IsTest
    static void eventAccountRecordsShipInactive() {
        Map<String, Humanitix_Object_Mapping__mdt> oms = new Map<String, Humanitix_Object_Mapping__mdt>();
        for (Humanitix_Object_Mapping__mdt om : HumanitixDefaultMappings.objectMappings()) {
            oms.put(om.DeveloperName, om);
        }
        Map<String, Humanitix_Field_Mapping__mdt> fms = new Map<String, Humanitix_Field_Mapping__mdt>();
        for (Humanitix_Field_Mapping__mdt fm : HumanitixDefaultMappings.fieldMappings()) {
            fms.put(fm.DeveloperName, fm);
        }

        Humanitix_Object_Mapping__mdt ea = oms.get('Event_to_Account');
        System.assertNotEquals(null, ea, 'Event_to_Account must ship');
        System.assertEquals(false, ea.Is_Active__c);
        System.assertEquals('Event', ea.Source_Resource__c);
        System.assertEquals('Account', ea.Target_SObject__c);
        System.assertEquals('Humanitix_Event_Id__c', ea.External_Id_Field__c);
        System.assertEquals('ExternalId', ea.Match_Strategy__c);
        System.assertEquals(14, ea.Load_Order__c);

        Humanitix_Field_Mapping__mdt key = fms.get('Event_to_Account_01');
        System.assertEquals('_id', key.Source_Path__c);
        System.assertEquals('Humanitix_Event_Id__c', key.Target_Field__c);
        System.assertEquals(true, key.Is_External_Id__c);

        Humanitix_Field_Mapping__mdt name = fms.get('Event_to_Account_02');
        System.assertEquals('Name', name.Target_Field__c);
        System.assertEquals('Template', name.Transform__c);
        System.assertEquals('Humanitix - {value}', name.Transform_Arg__c);

        Humanitix_Field_Mapping__mdt link = fms.get('Order_to_Contact_08');
        System.assertEquals('Order_to_Contact', link.Object_Mapping__c);
        System.assertEquals('eventId', link.Source_Path__c);
        System.assertEquals('AccountId', link.Target_Field__c);
        System.assertEquals('Reference', link.Data_Type__c);
        System.assertEquals('Account.Humanitix_Event_Id__c', link.Transform_Arg__c);
        System.assertEquals(false, link.Overwrite_Blank__c);
        System.assertEquals(false, link.Is_Active__c);
    }

    @IsTest
    static void personAccountRecordsShipInactive() {
        Humanitix_Object_Mapping__mdt pa;
        for (Humanitix_Object_Mapping__mdt om : HumanitixDefaultMappings.objectMappings()) {
            if (om.DeveloperName == 'Order_to_PersonAccount') {
                pa = om;
            }
        }
        System.assertNotEquals(null, pa, 'Order_to_PersonAccount must ship');
        System.assertEquals(false, pa.Is_Active__c);
        System.assertEquals('Order', pa.Source_Resource__c);
        System.assertEquals('Account', pa.Target_SObject__c);
        System.assertEquals('MatchByFields', pa.Match_Strategy__c);
        System.assertEquals('PersonEmail', pa.Match_Field_Set__c);
        System.assertEquals('BlanksOnly', pa.Update_Mode__c);
        System.assertEquals('Humanitix_Contact_Key__pc', pa.External_Id_Field__c);

        Map<String, String> targets = new Map<String, String>();
        Humanitix_Field_Mapping__mdt recordType;
        for (Humanitix_Field_Mapping__mdt fm : HumanitixDefaultMappings.fieldMappings()) {
            if (fm.Object_Mapping__c == 'Order_to_PersonAccount') {
                targets.put(fm.DeveloperName, fm.Target_Field__c);
                if (fm.DeveloperName == 'Order_to_PersonAccount_08') {
                    recordType = fm;
                }
            }
        }
        System.assertEquals(8, targets.size());
        System.assertEquals('PersonEmail', targets.get('Order_to_PersonAccount_04'));
        System.assertEquals('RecordTypeId', recordType.Target_Field__c);
        System.assertEquals(null, recordType.Source_Path__c);
        System.assertEquals(null, recordType.Default_Value__c, 'Filled per org when Person account is chosen');
    }
}
