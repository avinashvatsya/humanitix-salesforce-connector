/**
 * The connector's single DML path. Persists built SObjects for one Object Mapping
 * using its match strategy, always with partial-success DML (a bad record never
 * fails the batch) and FLS enforcement via Security.stripInaccessible.
 *
 * In-page duplicate keys are collapsed before DML (Humanitix pages can repeat a
 * record), so a page never trips "Duplicate external id specified" or a native
 * unique constraint.
 *
 * Strategies:
 *   ExternalId    - Database.upsert on the external id field (skip blank keys).
 *   MatchNoUpdate - insert only rows whose external id isn't already present.
 *   MatchByFields - match existing by a field set (e.g. CampaignId+ContactId),
 *                   update matches / insert the rest. Respects native unique keys.
 *   AlwaysCreate  - insert everything.
 */
public with sharing class HumanitixPersister {
    private static final Integer MAX_ERRORS = 20;

    public class PersistResult {
        public Integer processed = 0;
        public Integer failed = 0;
        public Integer skipped = 0;
        public List<String> errors = new List<String>();
    }

    public static PersistResult persist(HumanitixMappingConfig.ObjectMapping om, List<SObject> records) {
        PersistResult r = new PersistResult();
        if (records == null || records.isEmpty()) {
            return r;
        }
        String strat = String.isBlank(om.matchStrategy) ? 'ExternalId' : om.matchStrategy;
        switch on strat {
            when 'ExternalId' {
                upsertByExternalId(om, records, r);
            }
            when 'MatchNoUpdate' {
                matchNoUpdate(om, records, r);
            }
            when 'MatchByFields' {
                matchByFields(om, records, r);
            }
            when 'AlwaysCreate' {
                insertNew(records, r);
            }
            when else {
                upsertByExternalId(om, records, r);
            }
        }
        return r;
    }

    private static void upsertByExternalId(
        HumanitixMappingConfig.ObjectMapping om,
        List<SObject> records,
        PersistResult r
    ) {
        if (String.isBlank(om.externalIdField)) {
            throw new HumanitixMappingException(
                'Object Mapping "' + om.devName + '" uses ExternalId but defines no External Id Field.'
            );
        }
        Schema.SObjectField extf = fieldToken(om.targetSObject, om.externalIdField);
        Schema.DescribeFieldResult dfr = extf.getDescribe();
        if (!dfr.isCreateable() || !dfr.isUpdateable()) {
            throw new HumanitixMappingException(
                'Running user lacks create/update access to the external id field ' +
                om.targetSObject + '.' + om.externalIdField +
                ' — cannot upsert. Assign the Humanitix Integration Admin permission set.'
            );
        }
        // Collapse in-page duplicates so a repeated key can't trip DUPLICATE_EXTERNAL_ID.
        Map<String, SObject> byKey = new Map<String, SObject>();
        for (SObject s : records) {
            Object v = s.get(om.externalIdField);
            if (isBlankValue(v)) {
                r.skipped++;
                continue;
            }
            String k = String.valueOf(v);
            if (byKey.containsKey(k)) {
                r.skipped++;
            }
            byKey.put(k, s);
        }
        if (byKey.isEmpty()) {
            return;
        }
        List<SObject> clean = Security.stripInaccessible(AccessType.UPSERTABLE, byKey.values()).getRecords();
        tallyUpsert(Database.upsert(clean, extf, false), r);
    }

    private static void matchNoUpdate(
        HumanitixMappingConfig.ObjectMapping om,
        List<SObject> records,
        PersistResult r
    ) {
        if (String.isBlank(om.externalIdField)) {
            throw new HumanitixMappingException(
                'Object Mapping "' + om.devName + '" uses MatchNoUpdate but defines no External Id Field.'
            );
        }
        Map<String, SObject> byKey = new Map<String, SObject>();
        Set<String> keys = new Set<String>();
        for (SObject s : records) {
            Object v = s.get(om.externalIdField);
            if (isBlankValue(v)) {
                r.skipped++;
            } else {
                byKey.put(foldKey(v), s); // case-fold so it matches case-insensitive SOQL
                keys.add(String.valueOf(v));
            }
        }
        if (byKey.isEmpty()) {
            return;
        }
        String fld = HumanitixMappingConfig.safeIdentifier(om.externalIdField);
        String obj = HumanitixMappingConfig.safeIdentifier(om.targetSObject);
        String soql = 'SELECT ' + fld + ' FROM ' + obj + ' WHERE ' + fld + ' IN :keys';
        Set<String> existing = new Set<String>();
        for (SObject e : Database.query(soql, AccessLevel.SYSTEM_MODE)) {
            Object k = e.get(om.externalIdField);
            if (k != null) {
                existing.add(foldKey(k));
            }
        }
        List<SObject> toInsert = new List<SObject>();
        for (String k : byKey.keySet()) {
            if (existing.contains(k)) {
                r.skipped++;
            } else {
                toInsert.add(byKey.get(k));
            }
        }
        insertNew(toInsert, r);
    }

    private static void matchByFields(
        HumanitixMappingConfig.ObjectMapping om,
        List<SObject> records,
        PersistResult r
    ) {
        if (om.matchFields == null || om.matchFields.isEmpty()) {
            throw new HumanitixMappingException(
                'Object Mapping "' + om.devName + '" uses MatchByFields but defines no Match Field Set.'
            );
        }
        // Collapse in-page duplicates on the composite key so a repeated match key
        // can't violate a native unique constraint (e.g. CampaignMember).
        Map<String, SObject> byKey = new Map<String, SObject>();
        for (SObject s : records) {
            Boolean complete = true;
            for (String mf : om.matchFields) {
                if (isBlankValue(s.get(mf))) {
                    complete = false;
                    break;
                }
            }
            if (!complete) {
                r.skipped++;
                continue;
            }
            String k = keyOf(s, om.matchFields);
            if (byKey.containsKey(k)) {
                r.skipped++;
            }
            byKey.put(k, s);
        }
        if (byKey.isEmpty()) {
            return;
        }
        // Query existing rows filtered on EVERY match field (not just the first) to
        // keep the result set tight on low-cardinality leading fields.
        List<String> selectFields = new List<String>{ 'Id' };
        List<String> whereParts = new List<String>();
        Map<String, Object> binds = new Map<String, Object>();
        Integer i = 0;
        for (String mf : om.matchFields) {
            String safe = HumanitixMappingConfig.safeIdentifier(mf);
            selectFields.add(safe);
            Set<String> vals = new Set<String>();
            for (SObject s : byKey.values()) {
                vals.add(String.valueOf(s.get(mf)));
            }
            String bindName = 'b' + i;
            whereParts.add(safe + ' IN :' + bindName);
            binds.put(bindName, vals);
            i++;
        }
        String soql =
            'SELECT ' + String.join(selectFields, ', ') +
            ' FROM ' + HumanitixMappingConfig.safeIdentifier(om.targetSObject) +
            ' WHERE ' + String.join(whereParts, ' AND ');
        Map<String, Id> idByKey = new Map<String, Id>();
        for (SObject e : Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE)) {
            idByKey.put(keyOf(e, om.matchFields), (Id) e.get('Id'));
        }
        List<SObject> toInsert = new List<SObject>();
        List<SObject> toUpdate = new List<SObject>();
        for (SObject s : byKey.values()) {
            Id existingId = idByKey.get(keyOf(s, om.matchFields));
            if (existingId != null) {
                s.put('Id', existingId);
                toUpdate.add(s);
            } else {
                toInsert.add(s);
            }
        }
        updateExisting(toUpdate, r);
        insertNew(toInsert, r);
    }

    private static void insertNew(List<SObject> records, PersistResult r) {
        if (records.isEmpty()) {
            return;
        }
        List<SObject> clean = Security.stripInaccessible(AccessType.CREATABLE, records).getRecords();
        tallySave(Database.insert(clean, false), r);
    }

    private static void updateExisting(List<SObject> records, PersistResult r) {
        if (records.isEmpty()) {
            return;
        }
        List<SObject> clean = Security.stripInaccessible(AccessType.UPDATABLE, records).getRecords();
        tallySave(Database.update(clean, false), r);
    }

    // ---- helpers ----------------------------------------------------------

    private static Schema.SObjectField fieldToken(String sobjectName, String fieldName) {
        Schema.SObjectType st = HumanitixMappingConfig.globalDescribe().get(sobjectName);
        if (st == null) {
            throw new HumanitixMappingException('Unknown SObject: ' + sobjectName);
        }
        Schema.SObjectField f = st.getDescribe().fields.getMap().get(fieldName.toLowerCase());
        if (f == null) {
            throw new HumanitixMappingException('Unknown field ' + fieldName + ' on ' + sobjectName);
        }
        return f;
    }

    private static String keyOf(SObject s, List<String> fields) {
        List<String> parts = new List<String>();
        for (String f : fields) {
            parts.add(foldKey(s.get(f)));
        }
        return String.join(parts, '||');
    }

    /**
     * Case-folds a key so in-memory comparison matches SOQL's case-insensitive text
     * matching, while preserving case-sensitive Salesforce Ids (15/18-char) exactly.
     */
    private static String foldKey(Object v) {
        if (v == null) {
            return '';
        }
        String s = String.valueOf(v);
        if ((s.length() == 15 || s.length() == 18) && Pattern.matches('[a-zA-Z0-9]+', s)) {
            return s;
        }
        return s.toLowerCase();
    }

    private static Boolean isBlankValue(Object v) {
        return v == null || String.isBlank(String.valueOf(v));
    }

    private static void tallyUpsert(List<Database.UpsertResult> results, PersistResult r) {
        for (Database.UpsertResult u : results) {
            if (u.isSuccess()) {
                r.processed++;
            } else {
                r.failed++;
                addErrors(r, u.getErrors());
            }
        }
    }

    private static void tallySave(List<Database.SaveResult> results, PersistResult r) {
        for (Database.SaveResult sr : results) {
            if (sr.isSuccess()) {
                r.processed++;
            } else {
                r.failed++;
                addErrors(r, sr.getErrors());
            }
        }
    }

    private static void addErrors(PersistResult r, List<Database.Error> errors) {
        for (Database.Error e : errors) {
            if (r.errors.size() < MAX_ERRORS) {
                r.errors.add(e.getStatusCode() + ': ' + e.getMessage());
            }
        }
    }
}
