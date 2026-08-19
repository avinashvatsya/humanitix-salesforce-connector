/**
 * Direct record-builder tests for the field-mapping fallbacks (Default Source
 * Path and Default Value). The engine tests cover the shipped mappings end to
 * end; these pin the builder's own contract with hand-built mappings.
 */
@IsTest
private class HumanitixRecordBuilderTest {
    private static HumanitixMappingConfig.ObjectMapping tagMapping() {
        HumanitixMappingConfig.ObjectMapping om = new HumanitixMappingConfig.ObjectMapping();
        om.devName = 'Test_Tag';
        om.sourceResource = 'Tag';
        om.targetSObject = 'Humanitix_Tag__c';
        om.externalIdField = 'Humanitix_Id__c';
        om.matchStrategy = 'ExternalId';
        om.active = true;
        return om;
    }

    private static HumanitixMappingConfig.FieldMapping field(String sourcePath, String targetField) {
        HumanitixMappingConfig.FieldMapping f = new HumanitixMappingConfig.FieldMapping();
        f.sourcePath = sourcePath;
        f.targetField = targetField;
        f.dataType = 'Text';
        f.transform = 'None';
        f.isExternalId = false;
        f.overwriteBlank = true;
        f.active = true;
        return f;
    }

    private static List<HumanitixRecordBuilder.RecordContext> contexts(
        HumanitixMappingConfig.ObjectMapping om,
        String body
    ) {
        return HumanitixRecordBuilder.contextsFor(om, (List<Object>) JSON.deserializeUntyped('[' + body + ']'));
    }

    @IsTest
    static void defaultValueFillsBlankSourceAndYieldsToPresentValue() {
        HumanitixMappingConfig.ObjectMapping om = tagMapping();
        HumanitixMappingConfig.FieldMapping name = field('name', 'Name');
        name.defaultValue = 'Unknown';
        om.fields.add(field('_id', 'Humanitix_Id__c'));
        om.fields.add(name);

        HumanitixRecordBuilder.BuildOutput withValue = HumanitixRecordBuilder.build(
            om, contexts(om, '{"_id":"tag_1","name":"People"}')
        );
        HumanitixRecordBuilder.BuildOutput without = HumanitixRecordBuilder.build(
            om, contexts(om, '{"_id":"tag_2"}')
        );

        System.assertEquals('People', withValue.records[0].get('Name'), 'a present value must win over the default');
        System.assertEquals('Unknown', without.records[0].get('Name'), 'a missing value must fall back to the default');
        System.assertEquals('tag_2', without.records[0].get('Humanitix_Id__c'), 'fields without a default are untouched');
    }

    @IsTest
    static void defaultSourcePathBeatsFixedDefault() {
        HumanitixMappingConfig.ObjectMapping om = tagMapping();
        HumanitixMappingConfig.FieldMapping name = field('name', 'Name');
        name.defaultSourcePath = '_id';
        name.defaultValue = 'Unknown';
        om.fields.add(name);

        HumanitixRecordBuilder.BuildOutput out = HumanitixRecordBuilder.build(om, contexts(om, '{"_id":"tag_9"}'));

        System.assertEquals('tag_9', out.records[0].get('Name'), 'the default path is tried before the fixed value');
    }

    @IsTest
    static void referenceKeyFallsBackToDefaultPath() {
        HumanitixMappingConfig.ObjectMapping om = new HumanitixMappingConfig.ObjectMapping();
        om.devName = 'Test_Ticket_Type';
        om.sourceResource = 'Event';
        om.targetSObject = 'Humanitix_Ticket_Type__c';
        om.collectionPath = 'ticketTypes';
        om.active = true;
        HumanitixMappingConfig.FieldMapping evt = field('eventId', 'Humanitix_Event__c');
        evt.dataType = 'Reference';
        evt.transformArg = 'Humanitix_Event__c.Humanitix_Id__c';
        evt.defaultSourcePath = '$parent._id';
        om.fields.add(evt);

        HumanitixRecordBuilder.BuildOutput out = HumanitixRecordBuilder.build(
            om, contexts(om, '{"_id":"evt_1","ticketTypes":[{"_id":"tt_1"}]}')
        );

        System.assertEquals(1, out.refs.size(), 'the defaulted key must still produce a reference request');
        System.assertEquals('evt_1', out.refs[0].keyValue);
        System.assertEquals('Humanitix_Event__c', out.refs[0].targetObject);
        System.assertEquals('Humanitix_Id__c', out.refs[0].externalIdField);
        System.assertEquals('Humanitix_Event__c', out.refs[0].lookupField);
    }

    @IsTest
    static void noDefaultLeavesBlankBehaviourUnchanged() {
        HumanitixMappingConfig.ObjectMapping om = tagMapping();
        HumanitixMappingConfig.FieldMapping name = field('name', 'Name');
        name.overwriteBlank = false;
        om.fields.add(name);

        HumanitixRecordBuilder.BuildOutput out = HumanitixRecordBuilder.build(om, contexts(om, '{"_id":"tag_3"}'));

        System.assertEquals(false, out.records[0].isSet('Name'), 'a blank source with no default must not touch the field');
    }
}
