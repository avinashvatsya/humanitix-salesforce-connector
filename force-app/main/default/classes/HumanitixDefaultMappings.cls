/**
 * Reads the connector's default CustomMetadata records from the packaged
 * Humanitix_Default_Mappings static resource (JSON).
 *
 * The records cannot ship inside the package itself while the Summer '26
 * platform bug gacks every Metadata API deploy containing CustomMetadata
 * records, so the resource is the shipping vehicle. Three consumers:
 * HumanitixMappingSeeder seeds the records from it (first Setup-tab load or on
 * demand); HumanitixMappingConfig falls back to it at runtime while the org
 * has no mapping records, so a sync works out of the box; and Apex tests build
 * the same defaults in memory from it so they exercise the true shipped
 * configuration.
 */
public with sharing class HumanitixDefaultMappings {
    public static final String RESOURCE_NAME = 'Humanitix_Default_Mappings';

    /** One default CMT record: type + developer name + label + field values. */
    public class DefaultRecord {
        public String typeName;
        public String developerName;
        public String label;
        public Map<String, Object> values = new Map<String, Object>();

        /** Metadata API full name, e.g. Humanitix_Object_Mapping.Event_to_Campaign */
        public String fullName() {
            return typeName + '.' + developerName;
        }
    }

    private static List<DefaultRecord> cached;

    public static List<DefaultRecord> records() {
        if (cached == null) {
            cached = parse();
        }
        return cached;
    }

    public static List<Humanitix_Object_Mapping__mdt> objectMappings() {
        List<Humanitix_Object_Mapping__mdt> out = new List<Humanitix_Object_Mapping__mdt>();
        for (DefaultRecord r : records()) {
            if (r.typeName == 'Humanitix_Object_Mapping') {
                out.add((Humanitix_Object_Mapping__mdt) toSObject(r));
            }
        }
        return out;
    }

    public static List<Humanitix_Field_Mapping__mdt> fieldMappings() {
        List<Humanitix_Field_Mapping__mdt> out = new List<Humanitix_Field_Mapping__mdt>();
        for (DefaultRecord r : records()) {
            if (r.typeName == 'Humanitix_Field_Mapping') {
                out.add((Humanitix_Field_Mapping__mdt) toSObject(r));
            }
        }
        return out;
    }

    private static List<DefaultRecord> parse() {
        StaticResource res = [SELECT Body FROM StaticResource WHERE Name = :RESOURCE_NAME LIMIT 1];
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(res.Body.toString());
        List<DefaultRecord> out = new List<DefaultRecord>();
        for (Object o : (List<Object>) root.get('records')) {
            Map<String, Object> raw = (Map<String, Object>) o;
            DefaultRecord r = new DefaultRecord();
            r.typeName = (String) raw.get('type');
            r.developerName = (String) raw.get('developerName');
            r.label = (String) raw.get('label');
            r.values = (Map<String, Object>) raw.get('values');
            out.add(r);
        }
        return out;
    }

    /**
     * Builds an in-memory CMT sObject from a default record, coercing JSON
     * numbers to Decimal per the field describe (JSON.deserializeUntyped yields
     * Integer/Double, which sObject.put rejects for number fields).
     */
    private static SObject toSObject(DefaultRecord r) {
        Schema.SObjectType st = HumanitixMappingConfig.globalDescribe()
            .get(HumanitixMappingConfig.safeIdentifier(r.typeName + '__mdt'));
        if (st == null) {
            throw new HumanitixMappingException('Unknown default-mapping type: ' + r.typeName);
        }
        Map<String, Schema.SObjectField> flds = st.getDescribe().fields.getMap();
        SObject rec = st.newSObject();
        rec.put('DeveloperName', r.developerName);
        for (String field : r.values.keySet()) {
            Object raw = r.values.get(field);
            Schema.SObjectField f = flds.get(field.toLowerCase());
            if (raw == null || f == null) {
                continue;
            }
            if (f.getDescribe().getType() == Schema.DisplayType.DOUBLE) {
                rec.put(field, Decimal.valueOf(String.valueOf(raw)));
            } else {
                rec.put(field, raw);
            }
        }
        return rec;
    }
}
