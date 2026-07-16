/**
 * Loads and caches the connector's mapping configuration from the two Custom
 * Metadata Types (Humanitix Object Mapping + Humanitix Field Mapping) and
 * validates it against the org schema. This is the single source of truth for
 * where every Humanitix field lands — no object or field API name is hard-coded
 * in Apex, so an admin repoints data by editing metadata alone.
 */
public with sharing class HumanitixMappingConfig {
    public class ObjectMapping implements Comparable {
        public String devName;
        public String sourceResource;
        public String targetSObject;
        public String externalIdField;
        public String matchStrategy;
        public List<String> matchFields;
        public String collectionPath;
        public Decimal loadOrder;
        public Boolean active;
        public List<FieldMapping> fields = new List<FieldMapping>();

        public Integer compareTo(Object other) {
            Decimal o = ((ObjectMapping) other).loadOrder;
            if (loadOrder == o) {
                return 0;
            }
            return loadOrder < o ? -1 : 1;
        }
    }

    public class FieldMapping {
        public String sourcePath;
        public String targetField;
        public String dataType;
        public String transform;
        public String transformArg;
        public Boolean isExternalId;
        public Boolean overwriteBlank;
        public Boolean active;
    }

    private static HumanitixMappingConfig instance;
    private static Map<String, Schema.SObjectType> globalDescribeCache;

    /** Cached global describe — avoids re-materializing describes per mapping/DML. */
    public static Map<String, Schema.SObjectType> globalDescribe() {
        if (globalDescribeCache == null) {
            globalDescribeCache = Schema.getGlobalDescribe();
        }
        return globalDescribeCache;
    }

    /**
     * Guards an SObject/field API name before it is spliced into dynamic SOQL.
     * Names originate from validated CMT, but this is defense-in-depth against any
     * drift between validation and query time.
     */
    public static String safeIdentifier(String name) {
        if (String.isBlank(name) || !Pattern.matches('^[A-Za-z0-9_]+$', name)) {
            throw new HumanitixMappingException('Unsafe SObject/field identifier: ' + name);
        }
        return name;
    }

    public List<ObjectMapping> objectMappings = new List<ObjectMapping>();
    private Map<String, List<ObjectMapping>> byResource = new Map<String, List<ObjectMapping>>();

    public static HumanitixMappingConfig getInstance() {
        if (instance == null) {
            instance = load();
        }
        return instance;
    }

    @TestVisible
    private static void reset() {
        instance = null;
    }

    /** Test seam: inject a hand-built config instead of reading CMT. */
    @TestVisible
    private static void setInstance(HumanitixMappingConfig cfg) {
        instance = cfg;
    }

    private static HumanitixMappingConfig load() {
        HumanitixMappingConfig cfg = new HumanitixMappingConfig();
        Map<String, ObjectMapping> byName = new Map<String, ObjectMapping>();
        for (Humanitix_Object_Mapping__mdt om : [
            SELECT DeveloperName, Source_Resource__c, Source_Collection_Path__c, Target_SObject__c,
                External_Id_Field__c, Match_Strategy__c, Match_Field_Set__c,
                Load_Order__c, Is_Active__c
            FROM Humanitix_Object_Mapping__mdt
        ]) {
            ObjectMapping m = new ObjectMapping();
            m.devName = om.DeveloperName;
            m.sourceResource = om.Source_Resource__c;
            m.collectionPath = om.Source_Collection_Path__c;
            m.targetSObject = om.Target_SObject__c;
            m.externalIdField = om.External_Id_Field__c;
            m.matchStrategy = String.isBlank(om.Match_Strategy__c) ? 'ExternalId' : om.Match_Strategy__c;
            m.matchFields = splitCsv(om.Match_Field_Set__c);
            m.loadOrder = om.Load_Order__c == null ? 100 : om.Load_Order__c;
            m.active = om.Is_Active__c == true;
            byName.put(m.devName, m);
            cfg.objectMappings.add(m);
        }
        for (Humanitix_Field_Mapping__mdt fm : [
            SELECT Object_Mapping__c, Source_Path__c, Target_Field__c, Data_Type__c, Transform__c,
                Transform_Arg__c, Is_External_Id__c, Overwrite_Blank__c, Is_Active__c
            FROM Humanitix_Field_Mapping__mdt
        ]) {
            ObjectMapping parent = byName.get(fm.Object_Mapping__c);
            if (parent == null) {
                continue; // orphaned field mapping; ignore quietly
            }
            FieldMapping f = new FieldMapping();
            f.sourcePath = fm.Source_Path__c;
            f.targetField = fm.Target_Field__c;
            f.dataType = String.isBlank(fm.Data_Type__c) ? 'Text' : fm.Data_Type__c;
            f.transform = String.isBlank(fm.Transform__c) ? 'None' : fm.Transform__c;
            f.transformArg = fm.Transform_Arg__c;
            f.isExternalId = fm.Is_External_Id__c == true;
            f.overwriteBlank = fm.Overwrite_Blank__c != false; // default true
            f.active = fm.Is_Active__c != false; // default true
            parent.fields.add(f);
        }
        cfg.indexAndSort();
        return cfg;
    }

    private void indexAndSort() {
        for (ObjectMapping m : objectMappings) {
            if (!byResource.containsKey(m.sourceResource)) {
                byResource.put(m.sourceResource, new List<ObjectMapping>());
            }
            byResource.get(m.sourceResource).add(m);
        }
        for (List<ObjectMapping> lst : byResource.values()) {
            lst.sort();
        }
    }

    /** Test seam used by setInstance() paths. */
    @TestVisible
    private void rebuildIndex() {
        byResource = new Map<String, List<ObjectMapping>>();
        indexAndSort();
    }

    public List<ObjectMapping> activeForResource(String resource) {
        List<ObjectMapping> out = new List<ObjectMapping>();
        List<ObjectMapping> all = byResource.get(resource);
        if (all == null) {
            return out;
        }
        for (ObjectMapping m : all) {
            if (m.active) {
                out.add(m);
            }
        }
        return out;
    }

    /**
     * Validates every active mapping against the org schema. Returns a list of
     * human-readable problems (empty when the config is sound). The engine calls
     * this once per run and fails fast so a typo surfaces before any DML.
     */
    public List<String> validate() {
        List<String> errors = new List<String>();
        Map<String, Schema.SObjectType> gd = globalDescribe();
        for (ObjectMapping m : objectMappings) {
            if (!m.active) {
                continue;
            }
            Schema.SObjectType st = gd.get(m.targetSObject);
            if (st == null) {
                errors.add('Object Mapping "' + m.devName + '": unknown target SObject "' + m.targetSObject + '".');
                continue;
            }
            Map<String, Schema.SObjectField> flds = st.getDescribe().fields.getMap();

            // strategy prerequisites (fail fast before any DML)
            Boolean usesExtId = m.matchStrategy == 'ExternalId' || m.matchStrategy == 'MatchNoUpdate';
            if (usesExtId && String.isBlank(m.externalIdField)) {
                errors.add('Object Mapping "' + m.devName + '": strategy ' + m.matchStrategy + ' requires an External Id Field.');
            }
            if (m.matchStrategy == 'MatchByFields' && m.matchFields.isEmpty()) {
                errors.add('Object Mapping "' + m.devName + '": strategy MatchByFields requires a Match Field Set.');
            }
            if (String.isNotBlank(m.externalIdField) && !flds.containsKey(m.externalIdField.toLowerCase())) {
                errors.add('Object Mapping "' + m.devName + '": unknown external id field "' + m.externalIdField + '".');
            }
            for (String mf : m.matchFields) {
                if (!flds.containsKey(mf.toLowerCase())) {
                    errors.add('Object Mapping "' + m.devName + '": unknown match field "' + mf + '".');
                }
            }

            Boolean populatesExtId = false;
            for (FieldMapping f : m.fields) {
                if (!f.active) {
                    continue;
                }
                if (String.isBlank(f.targetField) || !flds.containsKey(f.targetField.toLowerCase())) {
                    errors.add('Field Mapping on "' + m.devName + '": unknown target field "' + f.targetField + '".');
                }
                if (String.isNotBlank(m.externalIdField) &&
                    m.externalIdField.equalsIgnoreCase(f.targetField)) {
                    populatesExtId = true;
                }
                if (f.dataType == 'Reference' && String.isNotBlank(f.transformArg)) {
                    validateReference(gd, f.transformArg, m.devName, errors);
                }
            }
            if (usesExtId && String.isNotBlank(m.externalIdField) && !populatesExtId) {
                errors.add('Object Mapping "' + m.devName + '": no active field mapping populates external id field "' + m.externalIdField + '".');
            }
        }
        return errors;
    }

    private void validateReference(
        Map<String, Schema.SObjectType> gd,
        String arg,
        String mappingName,
        List<String> errors
    ) {
        List<String> parts = arg.split('\\.');
        if (parts.size() != 2) {
            errors.add('Field Mapping on "' + mappingName + '": Reference arg must be "<Object>.<ExternalIdField>", got "' + arg + '".');
            return;
        }
        Schema.SObjectType st = gd.get(parts[0]);
        if (st == null) {
            errors.add('Field Mapping on "' + mappingName + '": unknown reference object "' + parts[0] + '".');
            return;
        }
        if (!st.getDescribe().fields.getMap().containsKey(parts[1].toLowerCase())) {
            errors.add('Field Mapping on "' + mappingName + '": unknown reference field "' + arg + '".');
        }
    }

    private static List<String> splitCsv(String csv) {
        List<String> out = new List<String>();
        if (String.isBlank(csv)) {
            return out;
        }
        for (String s : csv.split(',')) {
            if (String.isNotBlank(s)) {
                out.add(s.trim());
            }
        }
        return out;
    }
}
