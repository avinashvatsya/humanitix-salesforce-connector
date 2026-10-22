/**
 * Backs the Mappings tab of the Humanitix Setup console: browse object and
 * field mappings, edit them, create field mappings, and deactivate either
 * (CMT records cannot be deleted from Apex; deleted shipped records would be
 * re-seeded on upgrade anyway).
 *
 * Reads are the org's records plus every shipped default the org does not
 * have yet (flagged fromDefaults=true): on a fresh install that is all of
 * them, after an upgrade only the newly shipped ones. Every save deploys the
 * missing defaults alongside the edits, so a save never leaves the org with
 * a partial set.
 *
 * Validation reuses HumanitixMappingConfig.fromRecords().validate(): pending
 * edits are overlaid onto the effective records in memory and the candidate
 * config is validated exactly the way the sync engine will see it.
 */
public with sharing class HumanitixMappingAdminController {
    private static final String OBJECT_TYPE = 'Humanitix_Object_Mapping';
    private static final String FIELD_TYPE = 'Humanitix_Field_Mapping';
    private static final Set<String> DATA_TYPES = new Set<String>{
        'Text', 'LongText', 'DateTime', 'Date', 'Decimal', 'Currency',
        'Integer', 'Boolean', 'Email', 'Phone', 'Url', 'Reference'
    };
    private static final Set<String> TRANSFORMS = new Set<String>{
        'None', 'Trim', 'Upper', 'Lower', 'IsoToDateTime', 'IsoToDateInTz',
        'DecimalMoney', 'BoolMap', 'StaticValue', 'Concat', 'JoinArray', 'ToJson', 'Template'
    };

    public class ObjectMappingDto {
        @AuraEnabled public String devName;
        @AuraEnabled public String label;
        @AuraEnabled public String sourceResource;
        @AuraEnabled public String collectionPath;
        @AuraEnabled public String targetSObject;
        @AuraEnabled public String externalIdField;
        @AuraEnabled public String matchStrategy;
        @AuraEnabled public String matchFieldSet;
        @AuraEnabled public String updateMode;
        @AuraEnabled public Decimal loadOrder;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Integer fieldCount;
        @AuraEnabled public Boolean fromDefaults;
    }

    public class FieldMappingDto {
        @AuraEnabled public String devName;
        @AuraEnabled public String label;
        @AuraEnabled public String objectMapping;
        @AuraEnabled public String sourcePath;
        @AuraEnabled public String targetField;
        @AuraEnabled public String dataType;
        @AuraEnabled public String transform;
        @AuraEnabled public String transformArg;
        @AuraEnabled public String defaultSourcePath;
        @AuraEnabled public String defaultValue;
        @AuraEnabled public Boolean isExternalId;
        @AuraEnabled public Boolean overwriteBlank;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Boolean fromDefaults;
    }

    /** Pending edits from the UI. Field mappings with a blank devName are creates. */
    public class PendingChanges {
        public List<ObjectMappingDto> objectMappings = new List<ObjectMappingDto>();
        public List<FieldMappingDto> fieldMappings = new List<FieldMappingDto>();
    }

    public class FieldOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
    }

    @AuraEnabled
    public static List<ObjectMappingDto> getObjectMappings() {
        try {
            Map<String, Integer> fieldCounts = new Map<String, Integer>();
            for (Humanitix_Field_Mapping__mdt fm : effectiveFieldRecordsByName().values()) {
                String parent = fm.Object_Mapping__c;
                fieldCounts.put(parent, (fieldCounts.containsKey(parent) ? fieldCounts.get(parent) : 0) + 1);
            }
            List<ObjectMappingDto> out = new List<ObjectMappingDto>();
            for (Humanitix_Object_Mapping__mdt om : [
                SELECT DeveloperName, MasterLabel, Source_Resource__c, Source_Collection_Path__c,
                    Target_SObject__c, External_Id_Field__c, Match_Strategy__c, Match_Field_Set__c,
                    Update_Mode__c, Load_Order__c, Is_Active__c
                FROM Humanitix_Object_Mapping__mdt
            ]) {
                out.add(objectDtoFromRecord(om, fieldCounts));
            }
            for (HumanitixDefaultMappings.DefaultRecord r : missingDefaults(OBJECT_TYPE)) {
                out.add(objectDtoFromDefault(r, fieldCounts));
            }
            return sortedByLoadOrder(out);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<FieldMappingDto> getFieldMappings(String objectMappingDevName) {
        try {
            List<FieldMappingDto> out = new List<FieldMappingDto>();
            for (Humanitix_Field_Mapping__mdt fm : [
                SELECT DeveloperName, MasterLabel, Object_Mapping__c, Source_Path__c, Target_Field__c,
                    Data_Type__c, Transform__c, Transform_Arg__c, Default_Source_Path__c, Default_Value__c,
                    Is_External_Id__c, Overwrite_Blank__c, Is_Active__c
                FROM Humanitix_Field_Mapping__mdt
                WHERE Object_Mapping__c = :objectMappingDevName
                ORDER BY DeveloperName
            ]) {
                out.add(fieldDtoFromRecord(fm));
            }
            for (HumanitixDefaultMappings.DefaultRecord r : missingDefaults(FIELD_TYPE)) {
                if (objectMappingDevName == (String) r.values.get('Object_Mapping__c')) {
                    out.add(fieldDtoFromDefault(r));
                }
            }
            return out;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** Createable/updateable fields of the target SObject, for the target-field picker. */
    @AuraEnabled(cacheable=true)
    public static List<FieldOption> describeTargetFields(String sobjectApiName) {
        Schema.SObjectType st = HumanitixMappingConfig.globalDescribe()
            .get(HumanitixMappingConfig.safeIdentifier(sobjectApiName));
        if (st == null) {
            throw new AuraHandledException('Unknown object: ' + sobjectApiName);
        }
        Map<String, FieldOption> byName = new Map<String, FieldOption>();
        for (Schema.SObjectField f : st.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (!d.isCreateable() && !d.isUpdateable()) {
                continue;
            }
            FieldOption opt = new FieldOption();
            opt.value = d.getName();
            opt.label = d.getLabel() + ' (' + d.getName() + ')';
            opt.type = String.valueOf(d.getType());
            byName.put(d.getName(), opt);
        }
        List<String> names = new List<String>(byName.keySet());
        names.sort();
        List<FieldOption> out = new List<FieldOption>();
        for (String n : names) {
            out.add(byName.get(n));
        }
        return out;
    }

    /** Validates the pending edits against the org schema; empty list means clean. */
    @AuraEnabled
    public static List<String> validatePending(String pendingJson) {
        try {
            PendingChanges pending = parsePending(pendingJson);
            List<String> problems = structuralProblems(pending);
            if (!problems.isEmpty()) {
                return problems;
            }
            assignNewDevNames(pending);
            return candidateConfig(pending).validate();
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /** Validates, then deploys the pending edits. Returns the deploy job id (null in tests). */
    @AuraEnabled
    public static String savePending(String pendingJson) {
        try {
            PendingChanges pending = parsePending(pendingJson);
            return HumanitixMetadataWriter.deploy(deployRecordsFor(pending), 'Mappings');
        } catch (AuraHandledException e) {
            throw e;
        } catch (HumanitixMappingException e) {
            throw new AuraHandledException('Fix these problems before saving: ' + e.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException('The mapping deployment could not be started: ' + e.getMessage());
        }
    }

    /**
     * Shared by savePending and the Sync Settings Contact account save:
     * structural checks, new DeveloperNames, a full candidate-config validate,
     * then the records to deploy (always including missing shipped defaults).
     */
    public static List<Metadata.CustomMetadata> deployRecordsFor(PendingChanges pending) {
        List<String> problems = structuralProblems(pending);
        if (problems.isEmpty()) {
            assignNewDevNames(pending);
            problems = candidateConfig(pending).validate();
        }
        if (!problems.isEmpty()) {
            throw new HumanitixMappingException(String.join(problems, ' '));
        }
        return deployRecords(pending);
    }

    /** The org record, else the missing shipped default, else null. */
    public static ObjectMappingDto effectiveObjectMapping(String devName) {
        for (Humanitix_Object_Mapping__mdt om : [
            SELECT DeveloperName, MasterLabel, Source_Resource__c, Source_Collection_Path__c,
                Target_SObject__c, External_Id_Field__c, Match_Strategy__c, Match_Field_Set__c,
                Update_Mode__c, Load_Order__c, Is_Active__c
            FROM Humanitix_Object_Mapping__mdt
            WHERE DeveloperName = :devName
            LIMIT 1
        ]) {
            return objectDtoFromRecord(om, new Map<String, Integer>());
        }
        for (HumanitixDefaultMappings.DefaultRecord r : HumanitixDefaultMappings.records()) {
            if (r.typeName == OBJECT_TYPE && r.developerName == devName) {
                return objectDtoFromDefault(r, new Map<String, Integer>());
            }
        }
        return null;
    }

    /** The org record, else the missing shipped default, else null. */
    public static FieldMappingDto effectiveFieldMapping(String devName) {
        for (Humanitix_Field_Mapping__mdt fm : [
            SELECT DeveloperName, MasterLabel, Object_Mapping__c, Source_Path__c, Target_Field__c,
                Data_Type__c, Transform__c, Transform_Arg__c, Default_Source_Path__c, Default_Value__c,
                Is_External_Id__c, Overwrite_Blank__c, Is_Active__c
            FROM Humanitix_Field_Mapping__mdt
            WHERE DeveloperName = :devName
            LIMIT 1
        ]) {
            return fieldDtoFromRecord(fm);
        }
        for (HumanitixDefaultMappings.DefaultRecord r : HumanitixDefaultMappings.records()) {
            if (r.typeName == FIELD_TYPE && r.developerName == devName) {
                return fieldDtoFromDefault(r);
            }
        }
        return null;
    }

    @AuraEnabled
    public static Humanitix_Metadata_Deploy__c getDeployStatus(String jobId) {
        return HumanitixMetadataWriter.getDeployStatus(jobId);
    }

    // ---- pending helpers ---------------------------------------------------

    private static PendingChanges parsePending(String pendingJson) {
        try {
            PendingChanges pending = (PendingChanges) JSON.deserialize(pendingJson, PendingChanges.class);
            if (pending.objectMappings == null) {
                pending.objectMappings = new List<ObjectMappingDto>();
            }
            if (pending.fieldMappings == null) {
                pending.fieldMappings = new List<FieldMappingDto>();
            }
            return pending;
        } catch (Exception e) {
            throw new AuraHandledException('The pending changes payload could not be read: ' + e.getMessage());
        }
    }

    /** Cheap checks before the schema-level validate: enums, required fields, known parents. */
    @TestVisible
    private static List<String> structuralProblems(PendingChanges pending) {
        List<String> problems = new List<String>();
        Set<String> knownParents = effectiveObjectRecordsByName().keySet();
        for (ObjectMappingDto om : pending.objectMappings) {
            if (String.isBlank(om.devName)) {
                problems.add('An object mapping edit is missing its developer name.');
            } else if (!knownParents.contains(om.devName)) {
                problems.add('Unknown object mapping: ' + om.devName + '.');
            }
        }
        for (FieldMappingDto fm : pending.fieldMappings) {
            String rowName = String.isBlank(fm.devName) ? 'new field mapping' : fm.devName;
            if (String.isBlank(fm.objectMapping) || !knownParents.contains(fm.objectMapping)) {
                problems.add('Field mapping ' + rowName + ' has an unknown parent object mapping.');
            }
            if (String.isBlank(fm.targetField)) {
                problems.add('Field mapping ' + rowName + ' needs a target field.');
            }
            if (String.isNotBlank(fm.dataType) && !DATA_TYPES.contains(fm.dataType)) {
                problems.add('Field mapping ' + rowName + ' has an unknown data type: ' + fm.dataType + '.');
            }
            if (String.isNotBlank(fm.transform) && !TRANSFORMS.contains(fm.transform)) {
                problems.add('Field mapping ' + rowName + ' has an unknown transform: ' + fm.transform + '.');
            }
            if (fm.transform == 'Template' && (String.isBlank(fm.transformArg) || !fm.transformArg.contains('{value}'))) {
                problems.add('Field mapping ' + rowName + ' uses Template and needs a Transform Arg containing {value}, for example Humanitix - {value}.');
            }
            if (fm.transform == 'StaticValue') {
                if (String.isBlank(fm.transformArg)) {
                    problems.add('Field mapping ' + rowName + ' uses StaticValue and needs the literal in Transform Arg.');
                }
                if (String.isNotBlank(fm.defaultSourcePath) || String.isNotBlank(fm.defaultValue)) {
                    problems.add('Field mapping ' + rowName + ' uses StaticValue, which ignores Default Source Path and Default Value; clear them or choose another transform.');
                }
            }
        }
        return problems;
    }

    /**
     * Gives every created field mapping (blank devName) a stable name
     * <Parent>_C<NN>. Shipped defaults use <Parent>_<NN>, so the C infix can
     * never collide with a future package upgrade.
     */
    @TestVisible
    private static void assignNewDevNames(PendingChanges pending) {
        Set<String> taken = new Set<String>();
        for (String fullName : allKnownFieldMappingNames()) {
            taken.add(fullName);
        }
        for (FieldMappingDto fm : pending.fieldMappings) {
            if (String.isNotBlank(fm.devName)) {
                taken.add(fm.devName);
            }
        }
        for (FieldMappingDto fm : pending.fieldMappings) {
            if (String.isBlank(fm.devName)) {
                fm.devName = nextName(fm.objectMapping, taken);
                if (String.isBlank(fm.label)) {
                    fm.label = (fm.objectMapping + ' :: ' + fm.targetField).abbreviate(40);
                }
            }
        }
    }

    private static String nextName(String parentDevName, Set<String> taken) {
        for (Integer i = 1; i <= 99; i++) {
            String candidate = parentDevName + '_C' + (i < 10 ? '0' + String.valueOf(i) : String.valueOf(i));
            if (candidate.length() > 40) {
                throw new HumanitixMappingException('Generated name too long for ' + parentDevName);
            }
            if (!taken.contains(candidate)) {
                taken.add(candidate);
                return candidate;
            }
        }
        throw new HumanitixMappingException('No free custom mapping name left for ' + parentDevName);
    }

    /** Effective records with pending overlaid, translated through the engine's own loader. */
    private static HumanitixMappingConfig candidateConfig(PendingChanges pending) {
        Map<String, Humanitix_Object_Mapping__mdt> objects = effectiveObjectRecordsByName();
        for (ObjectMappingDto om : pending.objectMappings) {
            objects.put(om.devName, toObjectRecord(om));
        }
        Map<String, Humanitix_Field_Mapping__mdt> fields = effectiveFieldRecordsByName();
        for (FieldMappingDto fm : pending.fieldMappings) {
            fields.put(fm.devName, toFieldRecord(fm));
        }
        return HumanitixMappingConfig.fromRecords(objects.values(), fields.values());
    }

    /**
     * The records to deploy: every shipped default the org is missing (all of
     * them on a fresh install) with pending edits overlaid, plus the edits and
     * creates.
     */
    @TestVisible
    private static List<Metadata.CustomMetadata> deployRecords(PendingChanges pending) {
        Map<String, Metadata.CustomMetadata> byFullName = new Map<String, Metadata.CustomMetadata>();
        for (HumanitixDefaultMappings.DefaultRecord r : HumanitixMappingSeeder.missingDefaults()) {
            byFullName.put(r.fullName(), HumanitixMetadataWriter.record(r.fullName(), r.label, r.values));
        }
        for (ObjectMappingDto om : pending.objectMappings) {
            String fullName = OBJECT_TYPE + '.' + om.devName;
            byFullName.put(fullName, HumanitixMetadataWriter.record(
                fullName,
                String.isBlank(om.label) ? om.devName : om.label,
                objectValues(om)
            ));
        }
        for (FieldMappingDto fm : pending.fieldMappings) {
            String fullName = FIELD_TYPE + '.' + fm.devName;
            byFullName.put(fullName, HumanitixMetadataWriter.record(
                fullName,
                String.isBlank(fm.label) ? fm.devName : fm.label,
                fieldValues(fm)
            ));
        }
        return byFullName.values();
    }

    // ---- effective records -------------------------------------------------

    /** Shipped default records of one type that the org does not have yet. */
    private static List<HumanitixDefaultMappings.DefaultRecord> missingDefaults(String typeName) {
        List<HumanitixDefaultMappings.DefaultRecord> out = new List<HumanitixDefaultMappings.DefaultRecord>();
        for (HumanitixDefaultMappings.DefaultRecord r : HumanitixMappingSeeder.missingDefaults()) {
            if (r.typeName == typeName) {
                out.add(r);
            }
        }
        return out;
    }

    private static Map<String, Humanitix_Object_Mapping__mdt> effectiveObjectRecordsByName() {
        Map<String, Humanitix_Object_Mapping__mdt> out = new Map<String, Humanitix_Object_Mapping__mdt>();
        for (Humanitix_Object_Mapping__mdt om : [
            SELECT DeveloperName, Source_Resource__c, Source_Collection_Path__c, Target_SObject__c,
                External_Id_Field__c, Match_Strategy__c, Match_Field_Set__c,
                Update_Mode__c, Load_Order__c, Is_Active__c
            FROM Humanitix_Object_Mapping__mdt
        ]) {
            out.put(om.DeveloperName, om);
        }
        Set<String> missing = new Set<String>();
        for (HumanitixDefaultMappings.DefaultRecord r : missingDefaults(OBJECT_TYPE)) {
            missing.add(r.developerName);
        }
        for (Humanitix_Object_Mapping__mdt om : HumanitixDefaultMappings.objectMappings()) {
            if (missing.contains(om.DeveloperName)) {
                out.put(om.DeveloperName, om);
            }
        }
        return out;
    }

    private static Map<String, Humanitix_Field_Mapping__mdt> effectiveFieldRecordsByName() {
        Map<String, Humanitix_Field_Mapping__mdt> out = new Map<String, Humanitix_Field_Mapping__mdt>();
        for (Humanitix_Field_Mapping__mdt fm : [
            SELECT DeveloperName, Object_Mapping__c, Source_Path__c, Target_Field__c, Data_Type__c,
                Transform__c, Transform_Arg__c, Default_Source_Path__c, Default_Value__c,
                Is_External_Id__c, Overwrite_Blank__c, Is_Active__c
            FROM Humanitix_Field_Mapping__mdt
        ]) {
            out.put(fm.DeveloperName, fm);
        }
        for (HumanitixDefaultMappings.DefaultRecord r : missingDefaults(FIELD_TYPE)) {
            out.put(r.developerName, toFieldRecord(fieldDtoFromDefault(r)));
        }
        return out;
    }

    /** Load Order, then DeveloperName: org records and missing defaults interleave correctly. */
    private static List<ObjectMappingDto> sortedByLoadOrder(List<ObjectMappingDto> dtos) {
        Map<String, ObjectMappingDto> byKey = new Map<String, ObjectMappingDto>();
        for (ObjectMappingDto d : dtos) {
            Decimal order = d.loadOrder == null ? 100 : d.loadOrder;
            byKey.put(String.valueOf(order.setScale(2)).leftPad(12, '0') + '|' + d.devName, d);
        }
        List<String> keys = new List<String>(byKey.keySet());
        keys.sort();
        List<ObjectMappingDto> out = new List<ObjectMappingDto>();
        for (String k : keys) {
            out.add(byKey.get(k));
        }
        return out;
    }

    private static Set<String> allKnownFieldMappingNames() {
        Set<String> names = new Set<String>();
        for (SObject rec : Database.query('SELECT DeveloperName FROM Humanitix_Field_Mapping__mdt')) {
            names.add((String) rec.get('DeveloperName'));
        }
        for (HumanitixDefaultMappings.DefaultRecord r : HumanitixDefaultMappings.records()) {
            if (r.typeName == FIELD_TYPE) {
                names.add(r.developerName);
            }
        }
        return names;
    }

    // ---- translation -------------------------------------------------------

    private static ObjectMappingDto objectDtoFromRecord(
        Humanitix_Object_Mapping__mdt om,
        Map<String, Integer> fieldCounts
    ) {
        ObjectMappingDto dto = new ObjectMappingDto();
        dto.devName = om.DeveloperName;
        dto.label = om.MasterLabel;
        dto.sourceResource = om.Source_Resource__c;
        dto.collectionPath = om.Source_Collection_Path__c;
        dto.targetSObject = om.Target_SObject__c;
        dto.externalIdField = om.External_Id_Field__c;
        dto.matchStrategy = String.isBlank(om.Match_Strategy__c) ? 'ExternalId' : om.Match_Strategy__c;
        dto.matchFieldSet = om.Match_Field_Set__c;
        dto.updateMode = String.isBlank(om.Update_Mode__c) ? 'Always' : om.Update_Mode__c;
        dto.loadOrder = om.Load_Order__c;
        dto.active = om.Is_Active__c == true;
        dto.fieldCount = fieldCounts.containsKey(dto.devName) ? fieldCounts.get(dto.devName) : 0;
        dto.fromDefaults = false;
        return dto;
    }

    private static ObjectMappingDto objectDtoFromDefault(
        HumanitixDefaultMappings.DefaultRecord r,
        Map<String, Integer> fieldCounts
    ) {
        ObjectMappingDto dto = new ObjectMappingDto();
        dto.devName = r.developerName;
        dto.label = r.label;
        dto.sourceResource = (String) r.values.get('Source_Resource__c');
        dto.collectionPath = (String) r.values.get('Source_Collection_Path__c');
        dto.targetSObject = (String) r.values.get('Target_SObject__c');
        dto.externalIdField = (String) r.values.get('External_Id_Field__c');
        dto.matchStrategy = defaultString(r.values.get('Match_Strategy__c'), 'ExternalId');
        dto.matchFieldSet = (String) r.values.get('Match_Field_Set__c');
        dto.updateMode = defaultString(r.values.get('Update_Mode__c'), 'Always');
        dto.loadOrder = decimalOf(r.values.get('Load_Order__c'));
        dto.active = r.values.get('Is_Active__c') != false;
        dto.fieldCount = fieldCounts.containsKey(dto.devName) ? fieldCounts.get(dto.devName) : 0;
        dto.fromDefaults = true;
        return dto;
    }

    private static FieldMappingDto fieldDtoFromRecord(Humanitix_Field_Mapping__mdt fm) {
        FieldMappingDto dto = new FieldMappingDto();
        dto.devName = fm.DeveloperName;
        dto.label = fm.MasterLabel;
        dto.objectMapping = fm.Object_Mapping__c;
        dto.sourcePath = fm.Source_Path__c;
        dto.targetField = fm.Target_Field__c;
        dto.dataType = String.isBlank(fm.Data_Type__c) ? 'Text' : fm.Data_Type__c;
        dto.transform = String.isBlank(fm.Transform__c) ? 'None' : fm.Transform__c;
        dto.transformArg = fm.Transform_Arg__c;
        dto.defaultSourcePath = fm.Default_Source_Path__c;
        dto.defaultValue = fm.Default_Value__c;
        dto.isExternalId = fm.Is_External_Id__c == true;
        dto.overwriteBlank = fm.Overwrite_Blank__c != false;
        dto.active = fm.Is_Active__c != false;
        dto.fromDefaults = false;
        return dto;
    }

    private static FieldMappingDto fieldDtoFromDefault(HumanitixDefaultMappings.DefaultRecord r) {
        FieldMappingDto dto = new FieldMappingDto();
        dto.devName = r.developerName;
        dto.label = r.label;
        dto.objectMapping = (String) r.values.get('Object_Mapping__c');
        dto.sourcePath = (String) r.values.get('Source_Path__c');
        dto.targetField = (String) r.values.get('Target_Field__c');
        dto.dataType = defaultString(r.values.get('Data_Type__c'), 'Text');
        dto.transform = defaultString(r.values.get('Transform__c'), 'None');
        dto.transformArg = (String) r.values.get('Transform_Arg__c');
        dto.defaultSourcePath = (String) r.values.get('Default_Source_Path__c');
        dto.defaultValue = (String) r.values.get('Default_Value__c');
        dto.isExternalId = r.values.get('Is_External_Id__c') == true;
        dto.overwriteBlank = r.values.get('Overwrite_Blank__c') != false;
        dto.active = r.values.get('Is_Active__c') != false;
        dto.fromDefaults = true;
        return dto;
    }

    private static Humanitix_Object_Mapping__mdt toObjectRecord(ObjectMappingDto dto) {
        return new Humanitix_Object_Mapping__mdt(
            DeveloperName = dto.devName,
            Source_Resource__c = dto.sourceResource,
            Source_Collection_Path__c = dto.collectionPath,
            Target_SObject__c = dto.targetSObject,
            External_Id_Field__c = dto.externalIdField,
            Match_Strategy__c = dto.matchStrategy,
            Match_Field_Set__c = dto.matchFieldSet,
            Update_Mode__c = dto.updateMode,
            Load_Order__c = dto.loadOrder,
            Is_Active__c = dto.active == true
        );
    }

    private static Humanitix_Field_Mapping__mdt toFieldRecord(FieldMappingDto dto) {
        return new Humanitix_Field_Mapping__mdt(
            DeveloperName = dto.devName,
            Object_Mapping__c = dto.objectMapping,
            Source_Path__c = dto.sourcePath,
            Target_Field__c = dto.targetField,
            Data_Type__c = dto.dataType,
            Transform__c = dto.transform,
            Transform_Arg__c = dto.transformArg,
            Default_Source_Path__c = dto.defaultSourcePath,
            Default_Value__c = dto.defaultValue,
            Is_External_Id__c = dto.isExternalId == true,
            Overwrite_Blank__c = dto.overwriteBlank != false,
            Is_Active__c = dto.active != false
        );
    }

    private static Map<String, Object> objectValues(ObjectMappingDto dto) {
        return new Map<String, Object>{
            'Source_Resource__c' => dto.sourceResource,
            'Source_Collection_Path__c' => dto.collectionPath,
            'Target_SObject__c' => dto.targetSObject,
            'External_Id_Field__c' => dto.externalIdField,
            'Match_Strategy__c' => dto.matchStrategy,
            'Match_Field_Set__c' => dto.matchFieldSet,
            'Update_Mode__c' => dto.updateMode,
            'Load_Order__c' => dto.loadOrder,
            'Is_Active__c' => dto.active == true
        };
    }

    private static Map<String, Object> fieldValues(FieldMappingDto dto) {
        return new Map<String, Object>{
            'Object_Mapping__c' => dto.objectMapping,
            'Source_Path__c' => dto.sourcePath,
            'Target_Field__c' => dto.targetField,
            'Data_Type__c' => dto.dataType,
            'Transform__c' => dto.transform,
            'Transform_Arg__c' => dto.transformArg,
            'Default_Source_Path__c' => dto.defaultSourcePath,
            'Default_Value__c' => dto.defaultValue,
            'Is_External_Id__c' => dto.isExternalId == true,
            'Overwrite_Blank__c' => dto.overwriteBlank != false,
            'Is_Active__c' => dto.active != false
        };
    }

    private static String defaultString(Object raw, String fallback) {
        String s = (String) raw;
        return String.isBlank(s) ? fallback : s;
    }

    private static Decimal decimalOf(Object raw) {
        return raw == null ? null : Decimal.valueOf(String.valueOf(raw));
    }
}
