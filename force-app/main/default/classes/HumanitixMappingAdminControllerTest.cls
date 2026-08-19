@IsTest
private class HumanitixMappingAdminControllerTest {
    private static Boolean orgHasRecords() {
        return [SELECT COUNT() FROM Humanitix_Object_Mapping__mdt] > 0;
    }

    private static String pendingJson(
        List<HumanitixMappingAdminController.ObjectMappingDto> objects,
        List<HumanitixMappingAdminController.FieldMappingDto> fields
    ) {
        HumanitixMappingAdminController.PendingChanges pending = new HumanitixMappingAdminController.PendingChanges();
        pending.objectMappings = objects;
        pending.fieldMappings = fields;
        return JSON.serialize(pending);
    }

    private static HumanitixMappingAdminController.ObjectMappingDto findMapping(String devName) {
        for (HumanitixMappingAdminController.ObjectMappingDto dto : HumanitixMappingAdminController.getObjectMappings()) {
            if (dto.devName == devName) {
                return dto;
            }
        }
        return null;
    }

    private static HumanitixMappingAdminController.FieldMappingDto newFieldDto(String parent, String targetField) {
        HumanitixMappingAdminController.FieldMappingDto dto = new HumanitixMappingAdminController.FieldMappingDto();
        dto.devName = '';
        dto.objectMapping = parent;
        dto.sourcePath = 'eventName';
        dto.targetField = targetField;
        dto.dataType = 'Text';
        dto.transform = 'None';
        dto.active = true;
        dto.overwriteBlank = true;
        dto.isExternalId = false;
        return dto;
    }

    @IsTest
    static void objectMappingsReadInBothWorlds() {
        List<HumanitixMappingAdminController.ObjectMappingDto> mappings = HumanitixMappingAdminController.getObjectMappings();

        System.assert(!mappings.isEmpty(), 'Shipped defaults guarantee mappings even on a bare org');
        Boolean expectDefaults = !orgHasRecords();
        HumanitixMappingAdminController.ObjectMappingDto eventMapping = findMapping('Event_to_Event');
        System.assertNotEquals(null, eventMapping, 'Event_to_Event ships with the connector');
        System.assertEquals(expectDefaults, eventMapping.fromDefaults);
        System.assert(eventMapping.fieldCount > 0, 'Event_to_Event has field mappings');
        System.assertEquals('Humanitix_Event__c', eventMapping.targetSObject);
    }

    @IsTest
    static void fieldMappingsReadForKnownParent() {
        List<HumanitixMappingAdminController.FieldMappingDto> fields =
            HumanitixMappingAdminController.getFieldMappings('Event_to_Event');
        System.assert(!fields.isEmpty());
        for (HumanitixMappingAdminController.FieldMappingDto f : fields) {
            System.assertEquals('Event_to_Event', f.objectMapping);
            System.assert(String.isNotBlank(f.targetField));
        }
    }

    @IsTest
    static void describeTargetFieldsSortsAndFilters() {
        List<HumanitixMappingAdminController.FieldOption> options =
            HumanitixMappingAdminController.describeTargetFields('Contact');

        System.assert(!options.isEmpty());
        Set<String> names = new Set<String>();
        for (Integer i = 0; i < options.size(); i++) {
            names.add(options[i].value);
            if (i > 0) {
                System.assert(options[i - 1].value.compareTo(options[i].value) < 0, 'Options must be sorted');
            }
        }
        System.assert(names.contains('Email'), 'Writable standard field expected');
        System.assert(!names.contains('CreatedDate'), 'Read-only system field must be filtered');
    }

    @IsTest
    static void describeRejectsUnsafeAndUnknownObjects() {
        Boolean threwUnsafe = false;
        try {
            HumanitixMappingAdminController.describeTargetFields('Contact; DELETE');
        } catch (Exception e) {
            threwUnsafe = true;
        }
        System.assert(threwUnsafe, 'Unsafe identifier must be rejected');

        Boolean threwUnknown = false;
        try {
            HumanitixMappingAdminController.describeTargetFields('No_Such_Object__c');
        } catch (Exception e) {
            threwUnknown = true;
        }
        System.assert(threwUnknown, 'Unknown object must be rejected');
    }

    @IsTest
    static void validatePendingFlagsUnknownTargetField() {
        String payload = pendingJson(
            new List<HumanitixMappingAdminController.ObjectMappingDto>(),
            new List<HumanitixMappingAdminController.FieldMappingDto>{
                newFieldDto('Event_to_Event', 'No_Such_Field__c')
            }
        );

        List<String> problems = HumanitixMappingAdminController.validatePending(payload);

        System.assert(!problems.isEmpty(), 'Unknown target field must be reported');
        Boolean mentioned = false;
        for (String p : problems) {
            if (p.contains('No_Such_Field__c')) {
                mentioned = true;
            }
        }
        System.assert(mentioned, 'Problems should name the bad field: ' + String.join(problems, ' | '));
    }

    @IsTest
    static void validatePendingCleanForRealEdit() {
        HumanitixMappingAdminController.ObjectMappingDto edit = findMapping('Order_to_Contact');
        System.assertNotEquals(null, edit);
        edit.updateMode = 'Always';

        List<String> problems = HumanitixMappingAdminController.validatePending(
            pendingJson(
                new List<HumanitixMappingAdminController.ObjectMappingDto>{ edit },
                new List<HumanitixMappingAdminController.FieldMappingDto>()
            )
        );

        System.assertEquals(0, problems.size(), String.join(problems, ' | '));
    }

    @IsTest
    static void structuralProblemsRejectBadEnumsAndParents() {
        HumanitixMappingAdminController.FieldMappingDto bad = newFieldDto('Nope_Mapping', '');
        bad.dataType = 'Blob';
        bad.transform = 'Reverse';
        HumanitixMappingAdminController.PendingChanges pending = new HumanitixMappingAdminController.PendingChanges();
        pending.fieldMappings.add(bad);

        List<String> problems = HumanitixMappingAdminController.structuralProblems(pending);

        System.assertEquals(4, problems.size(), String.join(problems, ' | '));
    }

    @IsTest
    static void savePendingGeneratesCustomDevNames() {
        String payload = pendingJson(
            new List<HumanitixMappingAdminController.ObjectMappingDto>(),
            new List<HumanitixMappingAdminController.FieldMappingDto>{
                newFieldDto('Event_to_Event', 'Description__c'),
                newFieldDto('Event_to_Event', 'Timezone__c')
            }
        );

        Test.startTest();
        String jobId = HumanitixMappingAdminController.savePending(payload);
        Test.stopTest();

        System.assertEquals(null, jobId, 'Deploy returns null in test context');
        Set<String> fullNames = new Set<String>();
        for (Metadata.Metadata md : HumanitixMetadataWriter.lastContainer.getMetadata()) {
            fullNames.add(((Metadata.CustomMetadata) md).fullName);
        }
        System.assert(fullNames.contains('Humanitix_Field_Mapping.Event_to_Event_C01'), fullNames.toString());
        System.assert(fullNames.contains('Humanitix_Field_Mapping.Event_to_Event_C02'), fullNames.toString());
    }

    @IsTest
    static void savePendingMaterializesDefaultsOnlyOnBareOrg() {
        HumanitixMappingAdminController.ObjectMappingDto edit = findMapping('Event_to_Event');
        edit.active = false;
        String payload = pendingJson(
            new List<HumanitixMappingAdminController.ObjectMappingDto>{ edit },
            new List<HumanitixMappingAdminController.FieldMappingDto>()
        );

        Test.startTest();
        HumanitixMappingAdminController.savePending(payload);
        Test.stopTest();

        Integer deployed = HumanitixMetadataWriter.lastContainer.getMetadata().size();
        if (orgHasRecords()) {
            System.assertEquals(1, deployed, 'Seeded org deploys only the touched record');
        } else {
            System.assertEquals(
                HumanitixDefaultMappings.records().size(),
                deployed,
                'Bare org must materialize every default with the edit overlaid'
            );
        }
        for (Metadata.Metadata md : HumanitixMetadataWriter.lastContainer.getMetadata()) {
            Metadata.CustomMetadata cmt = (Metadata.CustomMetadata) md;
            if (cmt.fullName == 'Humanitix_Object_Mapping.Event_to_Event') {
                for (Metadata.CustomMetadataValue v : cmt.values) {
                    if (v.field == 'Is_Active__c') {
                        System.assertEquals(false, v.value, 'The pending edit must win');
                    }
                }
            }
        }
    }

    @IsTest
    static void savePendingRejectsInvalidChanges() {
        Boolean threw = false;
        try {
            HumanitixMappingAdminController.savePending(
                pendingJson(
                    new List<HumanitixMappingAdminController.ObjectMappingDto>(),
                    new List<HumanitixMappingAdminController.FieldMappingDto>{
                        newFieldDto('Event_to_Event', 'No_Such_Field__c')
                    }
                )
            );
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Invalid pending changes must not deploy');
        System.assertEquals(null, HumanitixMetadataWriter.lastContainer, 'Nothing may reach the writer');
    }

    @IsTest
    static void fieldMappingDefaultsRoundTripToTheDeployPayload() {
        HumanitixMappingAdminController.FieldMappingDto dto = newFieldDto('Event_to_Event', 'Description__c');
        dto.sourcePath = 'description';
        dto.defaultSourcePath = 'name';
        dto.defaultValue = 'No description';
        String payload = pendingJson(
            new List<HumanitixMappingAdminController.ObjectMappingDto>(),
            new List<HumanitixMappingAdminController.FieldMappingDto>{ dto }
        );

        Test.startTest();
        HumanitixMappingAdminController.savePending(payload);
        Test.stopTest();

        Map<String, Object> values;
        for (Metadata.Metadata md : HumanitixMetadataWriter.lastContainer.getMetadata()) {
            Metadata.CustomMetadata cmt = (Metadata.CustomMetadata) md;
            if (cmt.fullName == 'Humanitix_Field_Mapping.Event_to_Event_C01') {
                values = new Map<String, Object>();
                for (Metadata.CustomMetadataValue v : cmt.values) {
                    values.put(v.field, v.value);
                }
            }
        }
        System.assertNotEquals(null, values, 'the created mapping must be in the deploy payload');
        System.assertEquals('name', values.get('Default_Source_Path__c'));
        System.assertEquals('No description', values.get('Default_Value__c'));
    }

    @IsTest
    static void validatePendingFlagsAnUncoercibleDefaultValue() {
        HumanitixMappingAdminController.FieldMappingDto dto = newFieldDto('Event_to_Event', 'Total_Capacity__c');
        dto.sourcePath = 'totalCapacity';
        dto.dataType = 'Integer';
        dto.defaultValue = 'lots';

        List<String> problems = HumanitixMappingAdminController.validatePending(
            pendingJson(
                new List<HumanitixMappingAdminController.ObjectMappingDto>(),
                new List<HumanitixMappingAdminController.FieldMappingDto>{ dto }
            )
        );

        Boolean mentioned = false;
        for (String p : problems) {
            if (p.contains('Default Value "lots"')) {
                mentioned = true;
            }
        }
        System.assert(mentioned, 'the bad default must be reported: ' + String.join(problems, ' | '));
    }

    @IsTest
    static void fieldMappingDtosExposeTheDefaultSettings() {
        // Reads come from org records on a seeded org and from the shipped
        // resource on a bare one; either way the DTO must carry both settings
        // (null when unset) without failing to build.
        HumanitixMappingAdminController.FieldMappingDto lastName;
        for (HumanitixMappingAdminController.FieldMappingDto f : HumanitixMappingAdminController.getFieldMappings('Order_to_Contact')) {
            if (f.targetField == 'LastName') {
                lastName = f;
            }
        }
        System.assertNotEquals(null, lastName, 'Order_to_Contact maps LastName');
        System.assertEquals(null, lastName.defaultSourcePath, 'no shipped mapping uses a default path');
        if (!orgHasRecords()) {
            // The shipped resource carries Default Value "Unknown" on Order_to_Contact_03.
            System.assertEquals('Unknown', lastName.defaultValue, 'the shipped default must read through fieldDtoFromDefault');
        }
    }

    @IsTest
    static void structuralProblemsRejectStaticValueWithoutLiteralOrWithDefaults() {
        HumanitixMappingAdminController.FieldMappingDto dto = newFieldDto('Event_to_Event', 'Description__c');
        dto.sourcePath = null;
        dto.transform = 'StaticValue';
        dto.transformArg = null;
        dto.defaultValue = 'Unknown';
        HumanitixMappingAdminController.PendingChanges pending = new HumanitixMappingAdminController.PendingChanges();
        pending.fieldMappings.add(dto);

        List<String> problems = HumanitixMappingAdminController.structuralProblems(pending);

        System.assertEquals(2, problems.size(), String.join(problems, ' | '));
        System.assert(problems[0].contains('needs the literal in Transform Arg'), problems[0]);
        System.assert(problems[1].contains('ignores Default Source Path and Default Value'), problems[1]);

        dto.transformArg = 'In Progress';
        dto.defaultValue = null;
        System.assertEquals(0, HumanitixMappingAdminController.structuralProblems(pending).size(), 'a plain StaticValue mapping is fine');
    }
}
