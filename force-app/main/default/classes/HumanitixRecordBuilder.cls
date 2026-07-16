/**
 * Turns deserialized Humanitix JSON records into target SObjects for one Object
 * Mapping, using its Field Mappings. Non-reference fields are coerced and set
 * inline; reference fields become RefRequests for the RelationshipResolver.
 *
 * Handles nested-collection mappings (e.g. an event's ticketTypes[]) by expanding
 * each array element into its own context, with `$parent`/`$root` pointing at the
 * enclosing record.
 */
public with sharing class HumanitixRecordBuilder {
    public class RecordContext {
        public Map<String, Object> record;
        public Map<String, Object> parent;
        public Map<String, Object> root;

        public RecordContext(Map<String, Object> record, Map<String, Object> parent, Map<String, Object> root) {
            this.record = record;
            this.parent = parent;
            this.root = root;
        }
    }

    public class BuildOutput {
        public List<SObject> records = new List<SObject>();
        public List<HumanitixRelationshipResolver.RefRequest> refs = new List<HumanitixRelationshipResolver.RefRequest>();
    }

    /**
     * Expand a page of source records into the contexts to map for a given Object
     * Mapping. Plain mappings yield one context per record; collection mappings
     * yield one per array element with the enclosing record as parent/root.
     */
    public static List<RecordContext> contextsFor(HumanitixMappingConfig.ObjectMapping om, List<Object> records) {
        List<RecordContext> out = new List<RecordContext>();
        if (records == null) {
            return out;
        }
        for (Object o : records) {
            if (!(o instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> rec = (Map<String, Object>) o;
            if (String.isBlank(om.collectionPath)) {
                out.add(new RecordContext(rec, null, rec));
                continue;
            }
            Object coll = HumanitixJsonNavigator.valueAt(om.collectionPath, rec, null, rec);
            if (coll instanceof List<Object>) {
                for (Object item : (List<Object>) coll) {
                    if (item instanceof Map<String, Object>) {
                        out.add(new RecordContext((Map<String, Object>) item, rec, rec));
                    }
                }
            }
        }
        return out;
    }

    public static BuildOutput build(HumanitixMappingConfig.ObjectMapping om, List<RecordContext> contexts) {
        BuildOutput out = new BuildOutput();
        Schema.SObjectType st = HumanitixMappingConfig.globalDescribe().get(om.targetSObject);
        if (st == null) {
            throw new HumanitixMappingException('Unknown target SObject: ' + om.targetSObject);
        }
        for (RecordContext c : contexts) {
            SObject sob = st.newSObject();
            for (HumanitixMappingConfig.FieldMapping f : om.fields) {
                if (!f.active) {
                    continue;
                }
                // Isolate a single malformed value so it can't abort the whole page;
                // the record keeps the fields that mapped cleanly.
                try {
                    if (f.dataType == 'Reference') {
                        Object rawKey = HumanitixJsonNavigator.valueAt(f.sourcePath, c.record, c.parent, c.root);
                        Object normalized = HumanitixTypeCoercer.coerce(
                            rawKey, 'Text', f.transform, null, c.record, c.parent, c.root
                        );
                        String key = normalized == null ? null : String.valueOf(normalized);
                        if (String.isNotBlank(key) && String.isNotBlank(f.transformArg) && f.transformArg.contains('.')) {
                            List<String> parts = f.transformArg.split('\\.');
                            out.refs.add(
                                new HumanitixRelationshipResolver.RefRequest(sob, f.targetField, parts[0], parts[1], key)
                            );
                        }
                        continue;
                    }
                    Object value = HumanitixTypeCoercer.coerce(
                        HumanitixJsonNavigator.valueAt(f.sourcePath, c.record, c.parent, c.root),
                        f.dataType,
                        f.transform,
                        f.transformArg,
                        c.record,
                        c.parent,
                        c.root
                    );
                    if (value == null && !f.overwriteBlank) {
                        continue; // leave existing value intact
                    }
                    sob.put(f.targetField, value);
                } catch (Exception e) {
                    // Skip just this field; other fields on the record still map.
                    continue;
                }
            }
            out.records.add(sob);
        }
        return out;
    }
}
