/**
 * Resolves lookup/reference fields by external id, in bulk. The record builder
 * emits a RefRequest for every Reference field mapping; this class groups them by
 * (targetObject, externalIdField), issues one SOQL per group, and stamps the
 * resolved Id onto each record. Requests whose parent isn't found are left null —
 * children are never orphaned or pointed at the wrong parent.
 */
public with sharing class HumanitixRelationshipResolver {
    public class RefRequest {
        public SObject record;
        public String lookupField;
        public String targetObject;
        public String externalIdField;
        public String keyValue;

        public RefRequest(
            SObject record,
            String lookupField,
            String targetObject,
            String externalIdField,
            String keyValue
        ) {
            this.record = record;
            this.lookupField = lookupField;
            this.targetObject = targetObject;
            this.externalIdField = externalIdField;
            this.keyValue = keyValue;
        }
    }

    public static void resolve(List<RefRequest> refs) {
        if (refs == null || refs.isEmpty()) {
            return;
        }
        Map<String, Set<String>> keysByGroup = new Map<String, Set<String>>();
        for (RefRequest r : refs) {
            String g = r.targetObject + '.' + r.externalIdField;
            if (!keysByGroup.containsKey(g)) {
                keysByGroup.put(g, new Set<String>());
            }
            keysByGroup.get(g).add(r.keyValue);
        }

        Map<String, Map<String, Id>> idByKeyByGroup = new Map<String, Map<String, Id>>();
        for (String g : keysByGroup.keySet()) {
            List<String> parts = g.split('\\.');
            String obj = HumanitixMappingConfig.safeIdentifier(parts[0]);
            String fld = HumanitixMappingConfig.safeIdentifier(parts[1]);
            Set<String> keys = keysByGroup.get(g);
            Map<String, Id> idByKey = new Map<String, Id>();
            String soql = 'SELECT Id, ' + fld + ' FROM ' + obj + ' WHERE ' + fld + ' IN :keys';
            for (SObject s : Database.query(soql, AccessLevel.SYSTEM_MODE)) {
                Object k = s.get(parts[1]);
                if (k != null) {
                    // External id text fields match case-insensitively in SOQL, so
                    // normalize both sides to avoid a case-sensitive Map miss.
                    idByKey.put(normalize(k), (Id) s.get('Id'));
                }
            }
            idByKeyByGroup.put(g, idByKey);
        }

        for (RefRequest r : refs) {
            String g = r.targetObject + '.' + r.externalIdField;
            Id resolved = idByKeyByGroup.get(g).get(normalize(r.keyValue));
            if (resolved != null) {
                r.record.put(r.lookupField, resolved);
            }
        }
    }

    private static String normalize(Object key) {
        return key == null ? null : String.valueOf(key).toLowerCase();
    }
}
