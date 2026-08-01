# Contact Matching Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the work-in-progress `Update_Blanks_Only__c` checkbox with an `Update_Mode__c` picklist (`Always` | `BlanksOnly` | `Never`) on `Humanitix_Object_Mapping__mdt`, giving every mapping a full strategy × update-mode matrix in `HumanitixPersister`.

**Architecture:** `HumanitixMappingConfig` loads CMT into `ObjectMapping` wrappers consumed by `HumanitixPersister`, the single DML path. We swap the wrapper's `updateBlanksOnly : Boolean` for `updateMode : String`, route each match strategy through the mode inside the persister, and retire the redundant `MatchNoUpdate` strategy (its behaviour becomes `ExternalId` + `Never`). Nothing here has shipped in a released package version, so the checkbox and `MatchNoUpdate` are removed outright rather than deprecated.

**Tech Stack:** Salesforce Apex (API v62-era, `with sharing`), Custom Metadata Types, sf CLI v2, scratch org.

## Global Constraints

- Scratch/dev org alias is `htx-dev` (README default). If the user's org alias differs, substitute it in every command — ask before assuming.
- Git commits are authored solely by Avinash Vatsya. **Never add a `Co-Authored-By` trailer or any Claude credit.**
- The working tree contains unrelated uncommitted WIP. **Always `git add` the explicit paths listed in the task — never `git add -A` / `git add .`**
- CustomMetadata **records** cannot be deployed with `sf project deploy` (Summer '26 platform gack). Record XML is edited in source for future package builds, and org records are seeded via `Metadata.Operations` (Task 4). CustomField/class deploys are unaffected.
- Behaviour matrix being implemented (from the spec, reconciled with existing code):

| Match_Strategy__c | Update_Mode = Always (default) | BlanksOnly | Never |
|---|---|---|---|
| `ExternalId` | Upsert on external id (today's behaviour) | Pre-query by external id; fill only blank fields on existing; insert new | Insert only keys not already present (today's `MatchNoUpdate`) |
| `MatchByFields` | Match then full update; insert unmatched | Match then fill blanks only; insert unmatched (today's checkbox behaviour) | Matched rows untouched (counted `skipped`); insert unmatched |
| `AlwaysCreate` | Mode ignored — always inserts (documented) | ignored | ignored |

- Unknown `Update_Mode__c` values fail fast via `HumanitixMappingConfig.validate()` (same pattern as the existing MatchByFields/no-field-set check).

---

### Task 1: Add `Update_Mode__c` field metadata and sync the generators

**Files:**
- Create: `force-app/main/default/objects/Humanitix_Object_Mapping__mdt/fields/Update_Mode__c.field-meta.xml`
- Modify: `scripts/dev/generate-metadata.py:399-400` (Match_Strategy PICK values + new PICK)
- Modify: `scripts/dev/generate-default-mappings.py:71-77` (om() signature), `:164-176` (Order_to_Contact entry), `:338-339` (record emitter)
- Modify: `force-app/main/default/customMetadata/Humanitix_Object_Mapping.Order_to_Contact.md-meta.xml`

**Interfaces:**
- Produces: org + source field `Humanitix_Object_Mapping__mdt.Update_Mode__c` (Picklist: `Always` default, `BlanksOnly`, `Never`), which Task 2's config loader queries by exactly that API name.

- [ ] **Step 1: Create the picklist field metadata**

Write `force-app/main/default/objects/Humanitix_Object_Mapping__mdt/fields/Update_Mode__c.field-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Update_Mode__c</fullName>
    <fieldManageability>SubscriberControlled</fieldManageability>
    <label>Update Mode</label>
    <type>Picklist</type>
    <description>How matched/existing records are updated. Always (default): overwrite with the latest Humanitix values. BlanksOnly: fill only fields that are currently blank — never overwrite values the org already has. Never: leave matched records untouched; only new records are inserted. Ignored when Match Strategy is AlwaysCreate.</description>
    <valueSet>
        <valueSetDefinition>
            <sorted>false</sorted>
            <value>
                <fullName>Always</fullName>
                <default>true</default>
                <label>Always</label>
            </value>
            <value>
                <fullName>BlanksOnly</fullName>
                <default>false</default>
                <label>BlanksOnly</label>
            </value>
            <value>
                <fullName>Never</fullName>
                <default>false</default>
                <label>Never</label>
            </value>
        </valueSetDefinition>
    </valueSet>
</CustomField>
```

- [ ] **Step 2: Sync `generate-metadata.py`**

At lines 399-400, change the Match_Strategy PICK and add the new field directly after it:

```python
        PICK("Match_Strategy__c", ["ExternalId", "MatchByFields", "AlwaysCreate"],
             default="ExternalId", label="Match Strategy"),
        PICK("Update_Mode__c", ["Always", "BlanksOnly", "Never"],
             default="Always", label="Update Mode"),
```

(`MatchNoUpdate` is removed from the list — Task 3 removes it from the checked-in field XML.)

- [ ] **Step 3: Sync `generate-default-mappings.py`**

Three edits. First the `om()` helper (line 71):

```python
def om(dev, label, resource, target, ext_id_field=None, load=10,
       match="ExternalId", match_fields=None, update_mode="Always",
       collection=None, active=True, description=None, fields=None):
    return dict(dev=dev, label=label, resource=resource, target=target,
                ext_id_field=ext_id_field, load=load, match=match,
                match_fields=match_fields, update_mode=update_mode,
                collection=collection, active=active,
                description=description, fields=fields or [])
```

Second, the record emitter (after the `match_fields` block at lines 338-339):

```python
    if m["match_fields"]:
        rows.append(val("Match_Field_Set__c", m["match_fields"], "string"))
    if m["update_mode"] != "Always":
        rows.append(val("Update_Mode__c", m["update_mode"], "string"))
```

Third, the Order_to_Contact registry entry (line ~164) — bring the generator in line with the hand-edited XML (it currently omits the strategy/match-fields the record actually uses) and set the mode:

```python
MAPPINGS.append(om(
    "Order_to_Contact", "Order to Contact (buyer)", "Order", "Contact",
    ext_id_field="Humanitix_Contact_Key__c", load=18,
    match="MatchByFields", match_fields="Email", update_mode="BlanksOnly",
    description="Buyer becomes a Contact, matched to existing Contacts by Email (blanks-only "
                "updates: existing values are never overwritten). Orders without an email are skipped.",
    fields=[
        fm("email", "Humanitix_Contact_Key__c", "Text", "Lower", extid=True),
        fm("firstName", "FirstName"), fm("lastName", "LastName"),
        fm("email", "Email", "Email", "Lower"), fm("mobile", "MobilePhone", "Phone"),
        fm("organisation", "Humanitix_Organisation__c"),
        fm("_id", "Humanitix_Last_Order_Id__c"),
    ]))
```

Do **not** run the generator scripts in this task — the tree holds unrelated WIP and a regeneration could stomp hand edits elsewhere. The generators are being kept in sync as documentation-of-truth; the XML edits in Steps 1 and 4 are authoritative.

- [ ] **Step 4: Swap the value in the Order_to_Contact record XML**

In `force-app/main/default/customMetadata/Humanitix_Object_Mapping.Order_to_Contact.md-meta.xml`, replace:

```xml
    <values>
        <field>Update_Blanks_Only__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
```

with:

```xml
    <values>
        <field>Update_Mode__c</field>
        <value xsi:type="xsd:string">BlanksOnly</value>
    </values>
```

- [ ] **Step 5: Deploy the new field (field only — not the record)**

```bash
sf project deploy start -o htx-dev -m "CustomField:Humanitix_Object_Mapping__mdt.Update_Mode__c" -w 10
```

Expected: `Status: Succeeded`, 1 component deployed.

- [ ] **Step 6: Commit**

```bash
git add "force-app/main/default/objects/Humanitix_Object_Mapping__mdt/fields/Update_Mode__c.field-meta.xml" "scripts/dev/generate-metadata.py" "scripts/dev/generate-default-mappings.py" "force-app/main/default/customMetadata/Humanitix_Object_Mapping.Order_to_Contact.md-meta.xml"
git commit -m "feat: add Update_Mode picklist to object mapping metadata"
```

---

### Task 2: Config + persister matrix, test-first

**Files:**
- Modify: `force-app/main/default/classes/HumanitixPersisterTest.cls`
- Modify: `force-app/main/default/classes/HumanitixMappingConfig.cls:16,92,103,186-191`
- Modify: `force-app/main/default/classes/HumanitixPersister.cls`
- Modify: `force-app/main/default/classes/HumanitixMappingEngineTest.cls` (one appended test)

**Interfaces:**
- Consumes: `Humanitix_Object_Mapping__mdt.Update_Mode__c` from Task 1.
- Produces: `HumanitixMappingConfig.ObjectMapping.updateMode : String` (values `'Always'`|`'BlanksOnly'`|`'Never'`, never null — loader defaults blank to `'Always'`). `HumanitixPersister.persist(om, records)` signature unchanged. Private persister methods later tasks never touch: `insertIfAbsentByExternalId`, `externalIdBlanksOnly`, `addPopulatedFields`.

- [ ] **Step 1: Write the failing tests (red)**

In `HumanitixPersisterTest.cls`:

(a) **Replace** the whole `matchNoUpdateSkipsExistingAndBlankInsertsNew` method with:

```apex
    @IsTest
    static void externalIdNeverSkipsExistingAndBlankInsertsNew() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            insert tag('EXISTING');
            HumanitixMappingConfig.ObjectMapping om = tagMapping('ExternalId');
            om.updateMode = 'Never';
            Test.startTest();
            HumanitixPersister.PersistResult r = HumanitixPersister.persist(
                om,
                new List<SObject>{
                    tag('existing'), // same key, different case -> must not re-insert
                    tag('brand-new'),
                    new Humanitix_Tag__c(Name = 'blank') // no key -> skipped
                }
            );
            Test.stopTest();
            System.assertEquals(1, r.processed, 'only the new key inserts');
            System.assertEquals(2, r.skipped, 'existing (case-insensitive) and blank key skip');
            System.assertEquals(2, [SELECT COUNT() FROM Humanitix_Tag__c]);
        }
    }
```

(b) In `matchByFieldsBlanksOnlyPreservesExistingValues`, replace the line `om.updateBlanksOnly = true;` with:

```apex
            om.updateMode = 'BlanksOnly';
```

(c) **Add** two new test methods:

```apex
    @IsTest
    static void externalIdBlanksOnlyFillsBlanksPreservesValues() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            insert new List<Humanitix_Tag__c>{
                new Humanitix_Tag__c(Name = 'keep-me', Humanitix_Id__c = 'k1'), // User_Id__c blank
                new Humanitix_Tag__c(Name = 'full', Humanitix_Id__c = 'k3', User_Id__c = 'set')
            };
            HumanitixMappingConfig.ObjectMapping om = tagMapping('ExternalId');
            om.updateMode = 'BlanksOnly';
            Test.startTest();
            HumanitixPersister.PersistResult r = HumanitixPersister.persist(
                om,
                new List<SObject>{
                    new Humanitix_Tag__c(Name = 'clobber-attempt', Humanitix_Id__c = 'k1', User_Id__c = 'u9'),
                    new Humanitix_Tag__c(Name = 'fresh', Humanitix_Id__c = 'k2'),
                    new Humanitix_Tag__c(Name = 'noop', Humanitix_Id__c = 'k3', User_Id__c = 'y')
                }
            );
            Test.stopTest();
            System.assertEquals(3, r.processed, 'blank-fill update + insert + matched no-op all count');
            Humanitix_Tag__c k1 = [SELECT Name, User_Id__c FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'k1'];
            System.assertEquals('keep-me', k1.Name, 'existing value is never overwritten');
            System.assertEquals('u9', k1.User_Id__c, 'blank field is filled');
            Humanitix_Tag__c k3 = [SELECT Name, User_Id__c FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'k3'];
            System.assertEquals('full', k3.Name);
            System.assertEquals('set', k3.User_Id__c);
            System.assertEquals(3, [SELECT COUNT() FROM Humanitix_Tag__c]);
        }
    }

    @IsTest
    static void matchByFieldsNeverLeavesMatchedUntouched() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            insert new Humanitix_Tag__c(Name = 'old-name', Humanitix_Id__c = 'k1');
            HumanitixMappingConfig.ObjectMapping om = tagMapping('MatchByFields');
            om.matchFields = new List<String>{ 'Humanitix_Id__c' };
            om.updateMode = 'Never';
            Test.startTest();
            HumanitixPersister.PersistResult r = HumanitixPersister.persist(
                om,
                new List<SObject>{
                    new Humanitix_Tag__c(Name = 'new-name', Humanitix_Id__c = 'k1'),
                    new Humanitix_Tag__c(Name = 'fresh', Humanitix_Id__c = 'k2')
                }
            );
            Test.stopTest();
            System.assertEquals(1, r.processed, 'only the unmatched row inserts');
            System.assertEquals(1, r.skipped, 'matched row is left untouched');
            System.assertEquals('old-name',
                [SELECT Name FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'k1'].Name,
                'matched record is not modified');
            System.assertEquals(2, [SELECT COUNT() FROM Humanitix_Tag__c]);
        }
    }

    @IsTest
    static void externalIdBlanksOnlyBulk251() {
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            List<Humanitix_Tag__c> seed = new List<Humanitix_Tag__c>();
            for (Integer i = 0; i < 100; i++) {
                seed.add(new Humanitix_Tag__c(Name = 'seed-' + i, Humanitix_Id__c = 'bulk-' + i));
            }
            insert seed;
            List<SObject> page = new List<SObject>();
            for (Integer i = 0; i < 251; i++) {
                // first 100 match existing rows (Name must be preserved), rest are new
                page.add(new Humanitix_Tag__c(
                    Name = 'incoming-' + i, Humanitix_Id__c = 'bulk-' + i, User_Id__c = 'u' + i
                ));
            }
            HumanitixMappingConfig.ObjectMapping om = tagMapping('ExternalId');
            om.updateMode = 'BlanksOnly';
            Test.startTest();
            HumanitixPersister.PersistResult r = HumanitixPersister.persist(om, page);
            Test.stopTest();
            System.assertEquals(251, r.processed, 'all rows process: 100 blank-fills + 151 inserts');
            System.assertEquals(0, r.failed);
            System.assertEquals(251, [SELECT COUNT() FROM Humanitix_Tag__c]);
            System.assertEquals('seed-0',
                [SELECT Name FROM Humanitix_Tag__c WHERE Humanitix_Id__c = 'bulk-0'].Name,
                'existing names preserved at bulk scale');
        }
    }
```

(d) In `missingConfigThrowsClearErrors`, add after the existing `noExt` block:

```apex
        HumanitixMappingConfig.ObjectMapping noExtNever = tagMapping('ExternalId');
        noExtNever.externalIdField = null;
        noExtNever.updateMode = 'Never';
        try {
            HumanitixPersister.persist(noExtNever, new List<SObject>{ tag('t') });
            System.assert(false, 'expected HumanitixMappingException');
        } catch (HumanitixMappingException e) {
            System.assert(e.getMessage().contains('External Id Field'));
        }
```

- [ ] **Step 2: Add the stub property so the red deploy compiles**

In `HumanitixMappingConfig.cls`, directly under line 16 (`public Boolean updateBlanksOnly = false;`), add — do not remove anything yet:

```apex
        public String updateMode = 'Always';
```

- [ ] **Step 3: Deploy and verify the new tests fail for the right reason**

```bash
sf project deploy start -o htx-dev -m "ApexClass:HumanitixMappingConfig" -m "ApexClass:HumanitixPersisterTest" -w 10
sf apex run test -o htx-dev -t HumanitixPersisterTest -w 10 -r human
```

Expected: deploy succeeds; test run FAILS with exactly these failures (mode is not yet wired, so `ExternalId` blind-upserts and `MatchByFields` full-updates):
- `externalIdNeverSkipsExistingAndBlankInsertsNew` — `Expected: 1, Actual: 2` on `r.processed`
- `externalIdBlanksOnlyFillsBlanksPreservesValues` — `Expected: keep-me, Actual: clobber-attempt`
- `externalIdBlanksOnlyBulk251` — `Expected: seed-0, Actual: incoming-0`
- `matchByFieldsNeverLeavesMatchedUntouched` — `Expected: old-name, Actual: new-name`
- `matchByFieldsBlanksOnlyPreservesExistingValues` — `Expected: keep-me, Actual: clobber-attempt`
- `missingConfigThrowsClearErrors` — `expected HumanitixMappingException` (Never with no external id currently falls into plain upsert, which throws the *ExternalId* wording — assertion on message still passes since it contains 'External Id Field'; if the whole method passes, that is acceptable at red)

- [ ] **Step 4: Implement the config change (green, part 1)**

In `HumanitixMappingConfig.cls`:

(a) Delete line 16 `public Boolean updateBlanksOnly = false;` (keep the `updateMode` property added in Step 2).

(b) Line 92 SELECT list: replace `Load_Order__c, Is_Active__c, Update_Blanks_Only__c` with:

```apex
                Load_Order__c, Is_Active__c, Update_Mode__c
```

(c) Line 103: replace `m.updateBlanksOnly = om.Update_Blanks_Only__c == true;` with:

```apex
            m.updateMode = String.isBlank(om.Update_Mode__c) ? 'Always' : om.Update_Mode__c;
```

(d) Add a class-level constant under line 43 (`private static Map<String, Schema.SObjectType> globalDescribeCache;`):

```apex
    private static final Set<String> VALID_UPDATE_MODES = new Set<String>{ 'Always', 'BlanksOnly', 'Never' };
```

(e) In `validate()`, line 186: replace

```apex
            Boolean usesExtId = m.matchStrategy == 'ExternalId' || m.matchStrategy == 'MatchNoUpdate';
```

with

```apex
            Boolean usesExtId = m.matchStrategy == 'ExternalId';
```

and directly after the MatchByFields/no-field-set check (line 190-192) add:

```apex
            if (!VALID_UPDATE_MODES.contains(m.updateMode)) {
                errors.add('Object Mapping "' + m.devName + '": unknown Update Mode "' + m.updateMode + '" (use Always, BlanksOnly or Never).');
            }
```

- [ ] **Step 5: Implement the persister matrix (green, part 2)**

In `HumanitixPersister.cls`:

(a) Replace the class header comment's strategy list (lines 10-15) with:

```apex
 * Strategy × Update Mode matrix (Update_Mode__c applies to matched/existing rows):
 *   ExternalId    - Always: Database.upsert on the external id (skip blank keys).
 *                   BlanksOnly: pre-query existing; fill only blank fields; insert new.
 *                   Never: insert only keys not already present.
 *   MatchByFields - match existing by a field set (e.g. CampaignId+ContactId);
 *                   Always: update matches / BlanksOnly: fill blanks / Never: skip
 *                   matches. Unmatched rows always insert. Respects native unique keys.
 *   AlwaysCreate  - insert everything (Update Mode ignored).
```

(b) Replace the `switch on strat` block (lines 33-49) with:

```apex
        switch on strat {
            when 'ExternalId' {
                if (om.updateMode == 'Never') {
                    insertIfAbsentByExternalId(om, records, r);
                } else if (om.updateMode == 'BlanksOnly') {
                    externalIdBlanksOnly(om, records, r);
                } else {
                    upsertByExternalId(om, records, r);
                }
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
```

(c) Rename `matchNoUpdate` to `insertIfAbsentByExternalId` and update its guard message:

```apex
    private static void insertIfAbsentByExternalId(
        HumanitixMappingConfig.ObjectMapping om,
        List<SObject> records,
        PersistResult r
    ) {
        if (String.isBlank(om.externalIdField)) {
            throw new HumanitixMappingException(
                'Object Mapping "' + om.devName + '" uses Update Mode "Never" but defines no External Id Field.'
            );
        }
```

(rest of the method body is unchanged from the current `matchNoUpdate`).

(d) Add the new method after `insertIfAbsentByExternalId`:

```apex
    private static void externalIdBlanksOnly(
        HumanitixMappingConfig.ObjectMapping om,
        List<SObject> records,
        PersistResult r
    ) {
        if (String.isBlank(om.externalIdField)) {
            throw new HumanitixMappingException(
                'Object Mapping "' + om.devName + '" uses Update Mode "BlanksOnly" but defines no External Id Field.'
            );
        }
        Map<String, SObject> byKey = new Map<String, SObject>();
        Set<String> keys = new Set<String>();
        for (SObject s : records) {
            Object v = s.get(om.externalIdField);
            if (isBlankValue(v)) {
                r.skipped++;
                continue;
            }
            String k = foldKey(v);
            if (byKey.containsKey(k)) {
                r.skipped++;
            }
            byKey.put(k, s);
            keys.add(String.valueOf(v));
        }
        if (byKey.isEmpty()) {
            return;
        }
        String fld = HumanitixMappingConfig.safeIdentifier(om.externalIdField);
        String obj = HumanitixMappingConfig.safeIdentifier(om.targetSObject);
        List<String> selectFields = new List<String>{ 'Id', fld };
        addPopulatedFields(selectFields, byKey.values());
        String soql = 'SELECT ' + String.join(selectFields, ', ') + ' FROM ' + obj + ' WHERE ' + fld + ' IN :keys';
        Map<String, SObject> existingByKey = new Map<String, SObject>();
        for (SObject e : Database.query(soql, AccessLevel.SYSTEM_MODE)) {
            Object k = e.get(om.externalIdField);
            if (k != null) {
                existingByKey.put(foldKey(k), e);
            }
        }
        List<SObject> toInsert = new List<SObject>();
        List<SObject> toUpdate = new List<SObject>();
        for (String k : byKey.keySet()) {
            SObject s = byKey.get(k);
            SObject existing = existingByKey.get(k);
            if (existing != null) {
                SObject upd = blanksOnlyUpdate(s, existing);
                if (upd == null) {
                    r.processed++; // matched; nothing blank to fill — leave intact
                } else {
                    toUpdate.add(upd);
                }
            } else {
                toInsert.add(s);
            }
        }
        updateExisting(toUpdate, r);
        insertNew(toInsert, r);
    }
```

(e) In `matchByFields`, replace the blanks-only SELECT-widening block (lines 190-206, the `if (om.updateBlanksOnly == true) { ... }` that collects populated fields) with:

```apex
        if (om.updateMode == 'BlanksOnly') {
            // Blanks-only updates compare against current values, so query every
            // field the built records populate.
            addPopulatedFields(selectFields, byKey.values());
        }
```

and replace the matched-row branch (lines 217-234) with:

```apex
        List<SObject> toInsert = new List<SObject>();
        List<SObject> toUpdate = new List<SObject>();
        for (SObject s : byKey.values()) {
            SObject existing = existingByKey.get(keyOf(s, om.matchFields));
            if (existing != null) {
                if (om.updateMode == 'Never') {
                    r.skipped++; // matched — existing record left untouched
                } else if (om.updateMode == 'BlanksOnly') {
                    SObject upd = blanksOnlyUpdate(s, existing);
                    if (upd == null) {
                        r.processed++; // matched; nothing blank to fill — leave intact
                    } else {
                        toUpdate.add(upd);
                    }
                } else {
                    s.put('Id', existing.Id);
                    toUpdate.add(s);
                }
            } else {
                toInsert.add(s);
            }
        }
```

(f) Add the shared helper after `blanksOnlyUpdate`:

```apex
    /** Widens a SELECT field list with every field the built records populate. */
    private static void addPopulatedFields(List<String> selectFields, List<SObject> built) {
        Set<String> seen = new Set<String>();
        for (String sel : selectFields) {
            seen.add(sel.toLowerCase());
        }
        for (SObject s : built) {
            for (String f : s.getPopulatedFieldsAsMap().keySet()) {
                String safe = HumanitixMappingConfig.safeIdentifier(f);
                if (!seen.contains(safe.toLowerCase())) {
                    seen.add(safe.toLowerCase());
                    selectFields.add(safe);
                }
            }
        }
    }
```

- [ ] **Step 6: Add the config-validation test**

Append inside the class body of `HumanitixMappingEngineTest.cls` (before the final closing brace), matching that file's existing conventions:

```apex
    @IsTest
    static void validateRejectsUnknownUpdateMode() {
        HumanitixMappingConfig cfg = new HumanitixMappingConfig();
        HumanitixMappingConfig.ObjectMapping m = new HumanitixMappingConfig.ObjectMapping();
        m.devName = 'Bad_Mode_Mapping';
        m.sourceResource = 'Tag';
        m.targetSObject = 'Humanitix_Tag__c';
        m.externalIdField = 'Humanitix_Id__c';
        m.matchStrategy = 'ExternalId';
        m.loadOrder = 1;
        m.active = true;
        m.updateMode = 'Sometimes';
        cfg.objectMappings.add(m);
        List<String> errors = cfg.validate();
        Boolean found = false;
        for (String e : errors) {
            if (e.contains('unknown Update Mode "Sometimes"')) {
                found = true;
            }
        }
        System.assert(found, 'validate() must flag an unknown Update Mode; got: ' + errors);
    }
```

- [ ] **Step 7: Deploy and verify green**

```bash
sf project deploy start -o htx-dev -m "ApexClass:HumanitixMappingConfig" -m "ApexClass:HumanitixPersister" -m "ApexClass:HumanitixPersisterTest" -m "ApexClass:HumanitixMappingEngineTest" -w 10
sf apex run test -o htx-dev -t HumanitixPersisterTest -t HumanitixMappingEngineTest -w 10 -r human
```

Expected: deploy `Succeeded`; all tests PASS (including the pre-existing engine tests).

- [ ] **Step 8: Commit**

```bash
git add "force-app/main/default/classes/HumanitixMappingConfig.cls" "force-app/main/default/classes/HumanitixPersister.cls" "force-app/main/default/classes/HumanitixPersisterTest.cls" "force-app/main/default/classes/HumanitixMappingEngineTest.cls"
git commit -m "feat: strategy x update-mode matrix in persister (Always/BlanksOnly/Never)"
```

---

### Task 3: Remove the checkbox field and the MatchNoUpdate strategy value

**Files:**
- Delete: `force-app/main/default/objects/Humanitix_Object_Mapping__mdt/fields/Update_Blanks_Only__c.field-meta.xml`
- Modify: `force-app/main/default/objects/Humanitix_Object_Mapping__mdt/fields/Match_Strategy__c.field-meta.xml`

**Interfaces:**
- Consumes: Task 2 must be deployed first — after this task the org no longer has `Update_Blanks_Only__c`, and Task 2's config loader no longer queries it. Doing this before Task 2 would break the deployed loader.

- [ ] **Step 1: Confirm no CMT record still references either removal**

```bash
grep -rl "Update_Blanks_Only__c\|MatchNoUpdate" force-app/main/default/customMetadata/ || echo "CLEAN"
```

Expected: `CLEAN`. If any file lists, fix that record first (same edit as Task 1 Step 4).

- [ ] **Step 2: Delete the checkbox field from org and source**

```bash
sf project delete source -o htx-dev -m "CustomField:Humanitix_Object_Mapping__mdt.Update_Blanks_Only__c" --no-prompt
```

Expected: `Status: Succeeded`; the command deletes the field in the org **and** removes `Update_Blanks_Only__c.field-meta.xml` locally. Verify the file is gone: `ls force-app/main/default/objects/Humanitix_Object_Mapping__mdt/fields/ | grep Update` shows only `Update_Mode__c.field-meta.xml`.

- [ ] **Step 3: Remove `MatchNoUpdate` from the strategy picklist XML**

In `Match_Strategy__c.field-meta.xml`, delete the block:

```xml
            <value>
                <fullName>MatchNoUpdate</fullName>
                <default>false</default>
                <label>MatchNoUpdate</label>
            </value>
```

Then deploy:

```bash
sf project deploy start -o htx-dev -m "CustomField:Humanitix_Object_Mapping__mdt.Match_Strategy__c" -w 10
```

Expected: `Succeeded`. Note: a metadata deploy does not delete an already-existing picklist value in the org — that's fine for dev; fresh installs from source/package will never see it. No org record uses it (Step 1 proved that).

- [ ] **Step 4: Run the full local suite**

```bash
sf apex run test -o htx-dev -l RunLocalTests -w 30 -r human
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add "force-app/main/default/objects/Humanitix_Object_Mapping__mdt/fields/Match_Strategy__c.field-meta.xml"
git rm --cached --ignore-unmatch "force-app/main/default/objects/Humanitix_Object_Mapping__mdt/fields/Update_Blanks_Only__c.field-meta.xml" 2>/dev/null; git add -u "force-app/main/default/objects/Humanitix_Object_Mapping__mdt/fields/"
git commit -m "chore: remove Update_Blanks_Only checkbox and MatchNoUpdate strategy"
```

(The checkbox file was untracked WIP, so if `git status` shows nothing to commit for it, committing just the Match_Strategy change is correct.)

---

### Task 4: Seed the org record via Metadata.Operations + docs

**Files:**
- Create: `scripts/dev/seed-update-mode.apex`
- Modify: `docs/FIELD-MAPPING.md:18-19` and add a new section
- Modify: `docs/CONFIGURATION.md` (one new subsection; place it alongside the existing mapping-configuration prose)

**Interfaces:**
- Consumes: `Update_Mode__c` field (Task 1) deployed to the org.

- [ ] **Step 1: Write the seeding script**

Create `scripts/dev/seed-update-mode.apex`:

```apex
// Seeds Update_Mode__c on the Order_to_Contact mapping record via Metadata API,
// working around the Summer '26 gack on CustomMetadata record deploys.
// Run: sf apex run -f scripts/dev/seed-update-mode.apex -o <org>
Metadata.CustomMetadata rec = new Metadata.CustomMetadata();
rec.fullName = 'Humanitix_Object_Mapping.Order_to_Contact';
rec.label = 'Order to Contact (buyer)';
Metadata.CustomMetadataValue v = new Metadata.CustomMetadataValue();
v.field = 'Update_Mode__c';
v.value = 'BlanksOnly';
rec.values.add(v);
Metadata.DeployContainer c = new Metadata.DeployContainer();
c.addMetadata(rec);
Id jobId = Metadata.Operations.enqueueDeployment(c, null);
System.debug('Enqueued CMT deployment job: ' + jobId);
```

- [ ] **Step 2: Run it and verify the record**

```bash
sf apex run -f scripts/dev/seed-update-mode.apex -o htx-dev
```

Expected: `Compiled successfully.` / `Executed successfully.` Then wait ~30 seconds for the async metadata deploy and verify:

```bash
sf data query -q "SELECT DeveloperName, Update_Mode__c FROM Humanitix_Object_Mapping__mdt WHERE DeveloperName = 'Order_to_Contact'" -o htx-dev
```

Expected: one row, `Update_Mode__c = BlanksOnly`. (Metadata upserts merge — other values on the record are preserved.)

- [ ] **Step 3: Update FIELD-MAPPING.md**

Replace lines 18-19:

```markdown
| External Id Field | The upsert key field (used by `ExternalId` / `MatchNoUpdate`) |
| Match Strategy | `ExternalId`, `MatchByFields`, `MatchNoUpdate`, `AlwaysCreate` |
```

with:

```markdown
| External Id Field | The upsert key field (used by `ExternalId`) |
| Match Strategy | `ExternalId`, `MatchByFields`, `AlwaysCreate` |
| Update Mode | `Always` (default), `BlanksOnly`, `Never` — how matched/existing records are updated |
```

Then add this section after the table's section:

```markdown
## Update modes

`Update Mode` controls what happens when an incoming Humanitix record matches a
record that already exists in Salesforce:

| Match Strategy | `Always` (default) | `BlanksOnly` | `Never` |
| --- | --- | --- | --- |
| `ExternalId` | Upsert: existing records are updated with the latest Humanitix values | Only fields that are currently blank are filled; existing values are never overwritten | Existing records are left untouched; only new keys are inserted |
| `MatchByFields` | Matched records are fully updated | Matched records get blank fields filled only | Matched records are left untouched |
| `AlwaysCreate` | *(ignored — every row is inserted)* | *(ignored)* | *(ignored)* |

Unmatched/new records are always inserted in full, whatever the mode.

**Interaction with field-level `Overwrite Blank`:** `Overwrite Blank` on a Field
Mapping decides whether a *blank source value* may clear a populated target
field, and only applies when the mode allows the field to be written at all
(`Always`). Under `BlanksOnly`, populated target fields are never written,
so `Overwrite Blank` has no effect; under `Never`, nothing on a matched record
is written.

**Interaction with duplicate rules:** `AlwaysCreate` in an org whose duplicate
rules are set to *Block* will have those inserts rejected — they surface as
failed rows in the sync log (the run itself continues). Prefer `MatchByFields`
on Email, or set the duplicate rule to *Report*. `MatchByFields` updates at
most one existing record per key; which one is chosen when the org already
holds duplicates is not defined — merge duplicates first for deterministic
results.
```

- [ ] **Step 4: Update CONFIGURATION.md**

Add this subsection alongside the existing mapping-configuration guidance (keep the file's heading level conventions):

```markdown
### Choosing how buyer Contacts are matched

The `Order_to_Contact` mapping ships with Match Strategy `MatchByFields` on
`Email` and Update Mode `BlanksOnly`: buyers are de-duplicated against existing
Contacts by email, missing details are filled in, and values your org already
has are never overwritten. To let Humanitix data overwrite Salesforce
(`Always`), to leave matched Contacts completely untouched (`Never`), or to
always create new Contacts and let your own duplicate rules handle merging
(`AlwaysCreate`), edit the `Humanitix Object Mapping > Order_to_Contact` Custom
Metadata record — see [FIELD-MAPPING.md](FIELD-MAPPING.md#update-modes).
```

- [ ] **Step 5: Commit**

```bash
git add "scripts/dev/seed-update-mode.apex" "docs/FIELD-MAPPING.md" "docs/CONFIGURATION.md"
git commit -m "docs: document update modes; add CMT seed script for Order_to_Contact"
```

---

### Task 5: Full regression and release checklist

**Files:** none modified.

- [ ] **Step 1: Full Apex suite with coverage**

```bash
sf apex run test -o htx-dev -l RunLocalTests -c -w 30 -r human
```

Expected: all tests PASS; org-wide coverage at or above the pre-change baseline (≥75% required for packaging; `HumanitixPersister` should be well above).

- [ ] **Step 2: JS unit tests (unaffected, confirm no regression)**

```bash
npm run test:unit
```

Expected: PASS (or "no tests" if the LWC suite is empty — either is acceptable; only a failure blocks).

- [ ] **Step 3: Confirm the tree contains only intended changes**

```bash
git status --short
```

Expected: only the pre-existing unrelated WIP files remain modified; nothing from this plan is uncommitted.

- [ ] **Step 4: Record the release reminders (report to user, no commit)**

Report these two items in the final summary — they run at release time, not now:
1. **Kaipatiki org cleanup:** the WIP `Update_Blanks_Only__c` field may have been source-deployed to the client production org before this change. When releasing there: deploy the new code, run `scripts/dev/seed-update-mode.apex` against that org, then delete the leftover `Update_Blanks_Only__c` field (Setup → Custom Metadata Types → Humanitix Object Mapping → fields) if present.
2. **Package version:** build the next unlocked package version once the Summer '26 CMT-record deploy bug is fixed; until then, org record changes go through the seed script.
