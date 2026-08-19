# Field Mapping Default Values Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every Humanitix field mapping two fallbacks, a Default Source Path (another Humanitix field) and a fixed Default Value, evaluated when the mapped value is blank, and ship the result as package version 1.2.0 (installed in Kaipatiki prod with a green sync).

**Architecture:** Two new Text fields on `Humanitix_Field_Mapping__mdt` flow through `HumanitixMappingConfig.FieldMapping` into a fallback-aware `HumanitixTypeCoercer.coerce(...)` overload plus a `resolve(FieldMapping, ...)` entry point that `HumanitixRecordBuilder` (runtime) and `HumanitixMappingConfig.validate()` (fail-fast dry-run of a fixed default) both call. Precedence is Humanitix value, then default path, then fixed value; blankness is judged after the Transform and before Data Type coercion; Update Mode and Overwrite With Blank behave exactly as before. The Mappings tab editor, the admin controller DTO/queries/save maps and the shipped default records (Lead.Company single mapping, Contact.LastName default) carry the two settings end to end.

**Tech Stack:** Salesforce Apex (API 62.0, `with sharing`), Custom Metadata Types, LWC + Jest (`sfdx-lwc-jest`), Python generator scripts, sf CLI v2, 2GP unlocked package.

**Spec:** `docs/dev/specs/2026-08-19-default-values-design.md` (Approved 2026-08-19).

## Global Constraints

- **Dev Hub alias is `SAASKOOLProd`** (the hub that owns package `0HoOb00000001FRKAY`). **Dev scratch org alias is `htx-defaults`** (created in Task 1). Kaipatiki production alias is `KaipatikiProd`. Substitute nothing else.
- Git commits are authored solely by Avinash Vatsya (`avinash.vatsya@saaskool.com`), **with no `Co-Authored-By` or any other Claude trailer.** Always `git add` the explicit paths listed in the task, never `git add -A` / `git add .`.
- **No em dashes (`—`) in any user-facing text** written by this plan: CMT help text, LWC labels/help/messages, docs, README, release notes. Existing em dashes elsewhere in the docs are out of scope; do not add new ones.
- CustomMetadata **records** cannot be deployed with `sf project deploy` (Summer '26 platform gack, `**/customMetadata/**` is force-ignored). Record XML under `force-app/main/default/customMetadata/` is the source of truth; orgs get records from the `Humanitix_Default_Mappings` static resource via `HumanitixMappingSeeder`. **After any change under `customMetadata/`, delete stale record files first, then run `python3 scripts/dev/generate-mappings-resource.py`.**
- Package version: `1.1.0` is promoted, so `1.1.0.NEXT` is rejected by the platform. This release is **`1.2.0.NEXT`** ("Version 1.2"), built with `--code-coverage`, install-tested, promoted, then released as GitHub tag `v1.2.0-1`.
- Precedence and semantics being implemented (from the spec): Humanitix value at Source Path, else value at Default Source Path, else fixed Default Value; blank = null or whitespace-only string, judged after the Transform and before Data Type coercion; the winner goes through the same Transform and Data Type; `StaticValue` still short-circuits and ignores both defaults; `Reference` mappings apply the same fallback to the external-id key; Overwrite With Blank and Update Mode are unchanged.
- Code style: match the existing files (Apex 4-space indent, 120 columns; JS 2-space, single quotes, no trailing commas). Prettier is advisory in this repo (the baseline already fails `prettier:verify`), so do **not** reformat untouched code.
- Jest runs from the repo root with `npx sfdx-lwc-jest` (node modules already installed via `npm ci`; baseline 50/50 passing). Apex tests run in `htx-defaults`.
- Deploy Apex with `sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/classes --wait 10`; a compile error in a test class is the expected RED state before the implementation exists.

---

### Task 1: Add the two CMT fields and stand up the dev scratch org

**Files:**
- Modify: `scripts/dev/generate-metadata.py:455-459` (the `Transform_Arg__c` entry inside `CMTS["Humanitix_Field_Mapping__mdt"]`)
- Create (generated): `force-app/main/default/objects/Humanitix_Field_Mapping__mdt/fields/Default_Source_Path__c.field-meta.xml`
- Create (generated): `force-app/main/default/objects/Humanitix_Field_Mapping__mdt/fields/Default_Value__c.field-meta.xml`

**Interfaces:**
- Produces: `Humanitix_Field_Mapping__mdt.Default_Source_Path__c` (Text 255) and `Humanitix_Field_Mapping__mdt.Default_Value__c` (Text 255), SubscriberControlled, which Tasks 2 to 8 query and write by exactly those API names.

- [ ] **Step 1: Add the fields to the generator registry**

In `scripts/dev/generate-metadata.py`, directly after the `T("Transform_Arg__c", ...)` entry (which ends with `"For StaticValue: the literal value."),`) and before `dict(api="Is_External_Id__c", ...)`, insert:

```python
        T("Default_Source_Path__c", label="Default Source Path",
          helpText="Humanitix JSON path tried when the mapped value is blank after its Transform, "
                   "e.g. _id, email or $parent.name. Leave blank for no path fallback."),
        T("Default_Value__c", label="Default Value",
          helpText="Fixed text used when both the mapped value and the Default Source Path are blank. "
                   "It goes through the same Transform and Data Type coercion as the mapped value."),
```

- [ ] **Step 2: Regenerate and confirm only the two new files appear**

Run:
```bash
python3 scripts/dev/generate-metadata.py && git status --short
```
Expected: the summary line now reads `~224 fields total` (was 222) and `git status` shows exactly

```
 M scripts/dev/generate-metadata.py
?? force-app/main/default/objects/Humanitix_Field_Mapping__mdt/fields/Default_Source_Path__c.field-meta.xml
?? force-app/main/default/objects/Humanitix_Field_Mapping__mdt/fields/Default_Value__c.field-meta.xml
```

`Default_Source_Path__c.field-meta.xml` must be:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Default_Source_Path__c</fullName>
    <fieldManageability>SubscriberControlled</fieldManageability>
    <label>Default Source Path</label>
    <inlineHelpText>Humanitix JSON path tried when the mapped value is blank after its Transform, e.g. _id, email or $parent.name. Leave blank for no path fallback.</inlineHelpText>
    <type>Text</type>
    <length>255</length>
    <required>false</required>
</CustomField>
```

and `Default_Value__c.field-meta.xml` the same shape with `<fullName>Default_Value__c</fullName>`, `<label>Default Value</label>` and the second help text.

- [ ] **Step 3: Create the dev scratch org and deploy**

```bash
sf org create scratch --definition-file config/project-scratch-def.json --alias htx-defaults --duration-days 7 --wait 10 --target-dev-hub SAASKOOLProd
sf project deploy start --target-org htx-defaults --wait 30
sf org assign permset --name Humanitix_Integration_Admin --target-org htx-defaults
```
Expected: org created, deploy `Succeeded`, permset assigned. Do **not** seed the mapping records yet (Task 8 seeds after the resource is regenerated, so the dev org carries the new defaults).

- [ ] **Step 4: Prove the fields exist in the org**

```bash
sf data query --target-org htx-defaults --query "SELECT COUNT() FROM Humanitix_Field_Mapping__mdt WHERE Default_Value__c = null"
```
Expected: `Total number of records retrieved: 0` (no records yet, but the query compiles, so both fields exist).

- [ ] **Step 5: Baseline the Apex suite**

```bash
sf apex run test --target-org htx-defaults --test-level RunLocalTests --code-coverage --result-format human --wait 30
```
Expected: `Outcome: Passed`, 139 tests. Note the count; later tasks add to it.

- [ ] **Step 6: Commit**

```bash
git add scripts/dev/generate-metadata.py force-app/main/default/objects/Humanitix_Field_Mapping__mdt/fields/Default_Source_Path__c.field-meta.xml force-app/main/default/objects/Humanitix_Field_Mapping__mdt/fields/Default_Value__c.field-meta.xml
git commit -m "feat(metadata): add Default Source Path and Default Value to field mappings"
```

---

### Task 2: Config carries the two settings (data model, load, fromRecords)

**Files:**
- Modify: `force-app/main/default/classes/HumanitixMappingConfig.cls:34-43` (FieldMapping), `:118-123` (load SOQL), `:157-165` (fromRecords)
- Test: `force-app/main/default/classes/HumanitixMappingEngineTest.cls` (append one test)

**Interfaces:**
- Produces: `HumanitixMappingConfig.FieldMapping.defaultSourcePath : String` and `HumanitixMappingConfig.FieldMapping.defaultValue : String`, populated by `load()` and `fromRecords()` from `Default_Source_Path__c` / `Default_Value__c`. Tasks 3 to 8 read exactly these two property names.

- [ ] **Step 1: Write the failing test**

Append to `HumanitixMappingEngineTest` (before the final `}`):

```apex
    @IsTest
    static void fromRecordsCarriesTheDefaultSettings() {
        Humanitix_Object_Mapping__mdt om = new Humanitix_Object_Mapping__mdt(
            DeveloperName = 'Tag_Test',
            Source_Resource__c = 'Tag',
            Target_SObject__c = 'Humanitix_Tag__c',
            External_Id_Field__c = 'Humanitix_Id__c',
            Match_Strategy__c = 'ExternalId',
            Is_Active__c = true
        );
        Humanitix_Field_Mapping__mdt fm = new Humanitix_Field_Mapping__mdt(
            DeveloperName = 'Tag_Test_01',
            Object_Mapping__c = 'Tag_Test',
            Source_Path__c = 'name',
            Target_Field__c = 'Name',
            Data_Type__c = 'Text',
            Transform__c = 'Trim',
            Default_Source_Path__c = '_id',
            Default_Value__c = 'Unknown',
            Is_Active__c = true
        );

        HumanitixMappingConfig cfg = HumanitixMappingConfig.fromRecords(
            new List<Humanitix_Object_Mapping__mdt>{ om },
            new List<Humanitix_Field_Mapping__mdt>{ fm }
        );

        HumanitixMappingConfig.FieldMapping f = cfg.objectMappings[0].fields[0];
        System.assertEquals('_id', f.defaultSourcePath, 'Default_Source_Path__c must load into defaultSourcePath');
        System.assertEquals('Unknown', f.defaultValue, 'Default_Value__c must load into defaultValue');
    }
```

- [ ] **Step 2: Deploy to verify it fails**

```bash
sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/classes --wait 10
```
Expected: deploy **fails** with a compile error on `HumanitixMappingEngineTest`: `Variable does not exist: defaultSourcePath`.

- [ ] **Step 3: Add the properties and carry them through load() and fromRecords()**

In `HumanitixMappingConfig.cls`, change the `FieldMapping` class to:

```apex
    public class FieldMapping {
        public String sourcePath;
        public String targetField;
        public String dataType;
        public String transform;
        public String transformArg;
        public String defaultSourcePath;
        public String defaultValue;
        public Boolean isExternalId;
        public Boolean overwriteBlank;
        public Boolean active;
    }
```

In `load()`, change the field-mapping SOQL to:

```apex
        return fromRecords(objectRecords, [
            SELECT Object_Mapping__c, Source_Path__c, Target_Field__c, Data_Type__c, Transform__c,
                Transform_Arg__c, Default_Source_Path__c, Default_Value__c, Is_External_Id__c,
                Overwrite_Blank__c, Is_Active__c
            FROM Humanitix_Field_Mapping__mdt
        ]);
```

In `fromRecords()`, directly after `f.transformArg = fm.Transform_Arg__c;` add:

```apex
            f.defaultSourcePath = fm.Default_Source_Path__c;
            f.defaultValue = fm.Default_Value__c;
```

- [ ] **Step 4: Deploy and run the test**

```bash
sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/classes --wait 10
sf apex run test --target-org htx-defaults --class-names HumanitixMappingEngineTest --result-format human --wait 10
```
Expected: deploy `Succeeded`; `fromRecordsCarriesTheDefaultSettings` **Pass**, all other tests in the class still Pass.

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/classes/HumanitixMappingConfig.cls force-app/main/default/classes/HumanitixMappingEngineTest.cls
git commit -m "feat(config): load Default Source Path and Default Value into field mappings"
```

---

### Task 3: Coercer fallbacks and `resolve()` (test-first)

**Files:**
- Modify: `force-app/main/default/classes/HumanitixTypeCoercer.cls:1-31` (doc comment + `coerce`)
- Test: `force-app/main/default/classes/HumanitixTypeCoercerTest.cls` (append helper + seven tests)

**Interfaces:**
- Consumes: `HumanitixMappingConfig.FieldMapping` (`sourcePath`, `dataType`, `transform`, `transformArg`, `defaultSourcePath`, `defaultValue`) from Task 2; `HumanitixJsonNavigator.valueAt(path, record, parent, root)`.
- Produces:
  - `HumanitixTypeCoercer.coerce(Object raw, String dataType, String transform, String transformArg, String defaultSourcePath, String defaultValue, Map<String,Object> record, Map<String,Object> parent, Map<String,Object> root) : Object` (fallback-aware overload; the existing 7-argument `coerce` keeps working and delegates with null defaults).
  - `HumanitixTypeCoercer.resolve(HumanitixMappingConfig.FieldMapping f, Map<String,Object> record, Map<String,Object> parent, Map<String,Object> root) : Object` which reads the value at `f.sourcePath` and applies the fallbacks; for `dataType == 'Reference'` it coerces as `Text` with a null transform arg. Tasks 4 and 5 call `resolve`.

- [ ] **Step 1: Write the failing tests**

Append to `HumanitixTypeCoercerTest` (before the final `}`):

```apex
    private static Object coerceWithDefaults(
        Object raw,
        String type,
        String transform,
        String defaultPath,
        String defaultValue,
        Map<String, Object> rec
    ) {
        return HumanitixTypeCoercer.coerce(raw, type, transform, null, defaultPath, defaultValue, rec, null, rec);
    }

    @IsTest
    static void defaultsPreferValueThenPathThenFixed() {
        Map<String, Object> rec = new Map<String, Object>{ '_id' => 'ord_1' };
        System.assertEquals('Fellowship', coerceWithDefaults('Fellowship', 'Text', 'None', '_id', 'Unknown', rec), 'a present value wins');
        System.assertEquals('ord_1', coerceWithDefaults(null, 'Text', 'None', '_id', 'Unknown', rec), 'the default path is tried next');
        System.assertEquals('Unknown', coerceWithDefaults(null, 'Text', 'None', 'missing', 'Unknown', rec), 'the fixed value is last');
        System.assertEquals(null, coerceWithDefaults(null, 'Text', 'None', 'missing', null, rec), 'no default means null, as before');
    }

    @IsTest
    static void blankAfterTransformFallsThroughToTheDefault() {
        Map<String, Object> rec = new Map<String, Object>();
        System.assertEquals('Unknown', coerceWithDefaults('   ', 'Text', 'Trim', null, 'Unknown', rec), 'Trim to "" is blank');
        System.assertEquals('Unknown', coerceWithDefaults(new List<Object>(), 'Text', 'JoinArray', null, 'Unknown', rec), 'JoinArray of [] is blank');
        System.assertEquals('', coerceWithDefaults('', 'Text', 'None', null, null, rec), 'without a default an empty string is written as is');
    }

    @IsTest
    static void defaultGoesThroughTheTransformAndDataType() {
        Map<String, Object> rec = new Map<String, Object>();
        System.assertEquals('unknown', coerceWithDefaults(null, 'Text', 'Lower', null, 'UNKNOWN', rec), 'the transform applies to the default');
        Object dt = coerceWithDefaults(null, 'DateTime', 'IsoToDateTime', null, '2026-01-01T00:00:00.000Z', rec);
        System.assert(dt instanceof Datetime, 'the default must parse like a source value');
        System.assertEquals(2026, ((Datetime) dt).yearGmt());
        System.assertEquals(250, (Decimal) coerceWithDefaults(null, 'Integer', 'None', null, '250', rec), 'the data type coerces the default');
    }

    @IsTest
    static void booleanDefaultIsHonouredInsteadOfFalse() {
        Map<String, Object> rec = new Map<String, Object>();
        System.assertEquals(true, (Boolean) coerceWithDefaults(null, 'Boolean', 'BoolMap', null, 'true', rec));
        System.assertEquals(true, (Boolean) coerceWithDefaults(null, 'Boolean', 'None', null, 'yes', rec));
        System.assertEquals(false, (Boolean) coerceWithDefaults(null, 'Boolean', 'None', null, null, rec), 'no default keeps the unchecked fallback');
        System.assertEquals(false, (Boolean) coerceWithDefaults(false, 'Boolean', 'None', null, 'true', rec), 'an explicit false is a value, not a blank');
    }

    @IsTest
    static void staticValueIgnoresDefaults() {
        Map<String, Object> rec = new Map<String, Object>();
        Object v = HumanitixTypeCoercer.coerce(null, 'Text', 'StaticValue', 'In Progress', 'missing', 'Unknown', rec, null, rec);
        System.assertEquals('In Progress', (String) v, 'StaticValue short-circuits before the fallbacks');
    }

    @IsTest
    static void uncoercibleDefaultThrowsLikeAnyBadValue() {
        Boolean threw = false;
        try {
            coerceWithDefaults(null, 'Decimal', 'None', null, 'abc', new Map<String, Object>());
        } catch (Exception e) {
            threw = true;
        }
        System.assert(threw, 'a default the Data Type cannot coerce must surface as an exception');
    }

    @IsTest
    static void resolveReadsTheMappingAndTreatsReferenceAsText() {
        HumanitixMappingConfig.FieldMapping f = new HumanitixMappingConfig.FieldMapping();
        f.sourcePath = 'eventId';
        f.targetField = 'Humanitix_Event__c';
        f.dataType = 'Reference';
        f.transform = 'None';
        f.transformArg = 'Humanitix_Event__c.Humanitix_Id__c';
        f.defaultSourcePath = '$parent._id';
        Map<String, Object> parent = new Map<String, Object>{ '_id' => 'evt_1' };
        Map<String, Object> rec = new Map<String, Object>{ '_id' => 'tt_1' };

        System.assertEquals('evt_1', (String) HumanitixTypeCoercer.resolve(f, rec, parent, parent), 'the reference key falls back to the default path');

        rec.put('eventId', 'evt_2');
        System.assertEquals('evt_2', (String) HumanitixTypeCoercer.resolve(f, rec, parent, parent), 'a present key wins');
    }
```

- [ ] **Step 2: Deploy to verify it fails**

```bash
sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/classes --wait 10
```
Expected: deploy **fails**, compile errors on `HumanitixTypeCoercerTest`: `Method does not exist or incorrect signature: void coerce(...)` and `Method does not exist or incorrect signature: void resolve(...)`.

- [ ] **Step 3: Implement the fallback-aware coerce and resolve**

In `HumanitixTypeCoercer.cls`, replace the class doc comment's first paragraph and the whole existing `coerce` method (from `public static Object coerce(` through its closing `}`) with:

```apex
/**
 * Applies a transform then coerces a raw JSON value into the Apex type expected
 * by a target Salesforce field. Pure and side-effect free so it is trivial to unit
 * test with static fixtures.
 *
 * Field-mapping fallbacks: when the transformed Humanitix value is blank, the
 * value at the mapping's Default Source Path is tried, then its fixed Default
 * Value; the winner goes through the same transform and data type (see the
 * fallback-aware coerce overload and resolve()).
 *
 * Transforms: None, Trim, Upper, Lower, IsoToDateTime, IsoToDateInTz, DecimalMoney,
 * BoolMap, StaticValue, Concat, JoinArray, ToJson.
 * Data types:  Text, LongText, Email, Phone, Url, DateTime, Date, Decimal, Currency,
 * Integer, Boolean, Reference (Reference values are returned as normalized strings —
 * the RelationshipResolver turns them into Ids).
 *
 * Money note: Humanitix returns decimal major units (e.g. 53.98), so DecimalMoney is
 * a straight Decimal pass-through — never divide by 100.
 */
public with sharing class HumanitixTypeCoercer {
    /** Transform + coerce with no fallbacks (callers and tests that hold no field mapping). */
    public static Object coerce(
        Object raw,
        String dataType,
        String transform,
        String transformArg,
        Map<String, Object> record,
        Map<String, Object> parent,
        Map<String, Object> root
    ) {
        return coerce(raw, dataType, transform, transformArg, null, null, record, parent, root);
    }

    /**
     * Transform + coerce with the field-mapping fallbacks. When the transformed
     * Humanitix value is blank (null or a whitespace-only string), the value at
     * defaultSourcePath is transformed and used instead; when that is blank too,
     * the fixed defaultValue is transformed and used. Blankness is judged after
     * the transform and before type coercion, so a Trim/JoinArray result of ""
     * still triggers the fallback and a Boolean default is honoured (null is not
     * turned into false first). StaticValue ignores both fallbacks.
     */
    public static Object coerce(
        Object raw,
        String dataType,
        String transform,
        String transformArg,
        String defaultSourcePath,
        String defaultValue,
        Map<String, Object> record,
        Map<String, Object> parent,
        Map<String, Object> root
    ) {
        String t = String.isBlank(transform) ? 'None' : transform;
        if (t == 'StaticValue') {
            return coerceType(transformArg, dataType);
        }
        Object v = applyTransform(raw, t, transformArg, record, parent, root);
        if (isBlankValue(v) && String.isNotBlank(defaultSourcePath)) {
            Object fallback = HumanitixJsonNavigator.valueAt(defaultSourcePath, record, parent, root);
            v = applyTransform(fallback, t, transformArg, record, parent, root);
        }
        if (isBlankValue(v) && String.isNotBlank(defaultValue)) {
            v = applyTransform(defaultValue, t, transformArg, record, parent, root);
        }
        return coerceType(v, dataType);
    }

    /**
     * Resolves what one field mapping writes for a record context: the value at
     * its Source Path with the fallbacks applied, transformed and coerced.
     * Reference mappings are coerced as Text with no transform arg, because their
     * arg slot holds the Object.ExternalIdField the RelationshipResolver matches on.
     */
    public static Object resolve(
        HumanitixMappingConfig.FieldMapping f,
        Map<String, Object> record,
        Map<String, Object> parent,
        Map<String, Object> root
    ) {
        Boolean isReference = f.dataType == 'Reference';
        return coerce(
            HumanitixJsonNavigator.valueAt(f.sourcePath, record, parent, root),
            isReference ? 'Text' : f.dataType,
            f.transform,
            isReference ? null : f.transformArg,
            f.defaultSourcePath,
            f.defaultValue,
            record,
            parent,
            root
        );
    }

    /** Blank means "Humanitix has nothing here": null, or a whitespace-only string. */
    private static Boolean isBlankValue(Object v) {
        if (v == null) {
            return true;
        }
        return (v instanceof String) && String.isBlank((String) v);
    }
```

The rest of the class (`applyTransform`, `coerceType`, helpers) is unchanged.

- [ ] **Step 4: Deploy and run the coercer tests**

```bash
sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/classes --wait 10
sf apex run test --target-org htx-defaults --class-names HumanitixTypeCoercerTest --result-format human --wait 10
```
Expected: `Succeeded`; all 20 tests in `HumanitixTypeCoercerTest` **Pass** (13 existing + 7 new).

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/classes/HumanitixTypeCoercer.cls force-app/main/default/classes/HumanitixTypeCoercerTest.cls
git commit -m "feat(coercer): fall back to Default Source Path then Default Value when the value is blank"
```

---

### Task 4: `validate()` rejects a fixed default the Data Type cannot coerce

**Files:**
- Modify: `force-app/main/default/classes/HumanitixMappingConfig.cls` (constant, `validate()` field loop, new private method)
- Test: `force-app/main/default/classes/HumanitixMappingEngineTest.cls` (append one test)

**Interfaces:**
- Consumes: `HumanitixTypeCoercer.resolve(FieldMapping, record, parent, root)` from Task 3.
- Produces: `validate()` error text of the form `Field Mapping on "<devName>": Default Value "<value>" for <targetField> is not a valid <DataType>.` (or `... is not a valid <DataType> with transform <Transform>.` when a transform other than None is set). Task 6's controller test asserts on `Default Value "lots"`.

- [ ] **Step 1: Write the failing test**

Append to `HumanitixMappingEngineTest`:

```apex
    @IsTest
    static void validateRejectsADefaultValueTheDataTypeCannotCoerce() {
        HumanitixMappingConfig cfg = new HumanitixMappingConfig();
        HumanitixMappingConfig.ObjectMapping m = new HumanitixMappingConfig.ObjectMapping();
        m.devName = 'Bad_Default_Mapping';
        m.sourceResource = 'Event';
        m.targetSObject = 'Humanitix_Event__c';
        m.externalIdField = 'Humanitix_Id__c';
        m.matchStrategy = 'ExternalId';
        m.loadOrder = 1;
        m.active = true;
        HumanitixMappingConfig.FieldMapping id = new HumanitixMappingConfig.FieldMapping();
        id.sourcePath = '_id';
        id.targetField = 'Humanitix_Id__c';
        id.dataType = 'Text';
        id.transform = 'None';
        id.active = true;
        HumanitixMappingConfig.FieldMapping cap = new HumanitixMappingConfig.FieldMapping();
        cap.sourcePath = 'totalCapacity';
        cap.targetField = 'Total_Capacity__c';
        cap.dataType = 'Integer';
        cap.transform = 'None';
        cap.defaultValue = 'lots';
        cap.active = true;
        m.fields.add(id);
        m.fields.add(cap);
        cfg.objectMappings.add(m);

        List<String> errors = cfg.validate();

        Boolean found = false;
        for (String e : errors) {
            if (e.contains('Default Value "lots"') && e.contains('Integer')) {
                found = true;
            }
        }
        System.assert(found, 'validate() must flag a default the Data Type cannot coerce; got: ' + errors);

        cap.defaultValue = '250';
        List<String> clean = cfg.validate();
        System.assertEquals(0, clean.size(), 'a coercible default must validate cleanly; got: ' + clean);
    }
```

- [ ] **Step 2: Deploy and run to verify it fails**

```bash
sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/classes --wait 10
sf apex run test --target-org htx-defaults --class-names HumanitixMappingEngineTest --result-format human --wait 10
```
Expected: deploy `Succeeded` (the test compiles); `validateRejectsADefaultValueTheDataTypeCannotCoerce` **Fail** with `validate() must flag a default the Data Type cannot coerce; got: ()`.

- [ ] **Step 3: Implement the dry-run**

In `HumanitixMappingConfig.cls`, after the `VALID_MATCH_STRATEGIES` constant add:

```apex
    private static final Map<String, Object> EMPTY_RECORD = new Map<String, Object>();
```

In `validate()`, inside `for (FieldMapping f : m.fields)`, directly after

```apex
                if (f.dataType == 'Reference' && String.isNotBlank(f.transformArg)) {
                    validateReference(gd, f.transformArg, m.devName, errors);
                }
```
add:
```apex
                if (String.isNotBlank(f.defaultValue)) {
                    validateDefaultValue(f, m.devName, errors);
                }
```

After the `validateReference` method add:

```apex
    /**
     * Dry-runs the fixed default through the mapping's Transform and Data Type
     * against an empty record, so a default that cannot be coerced (say "abc"
     * for a Decimal field) fails the run before any DML, like every other
     * configuration mistake.
     */
    private void validateDefaultValue(FieldMapping f, String mappingName, List<String> errors) {
        try {
            HumanitixTypeCoercer.resolve(f, EMPTY_RECORD, null, EMPTY_RECORD);
        } catch (Exception e) {
            String how = (String.isBlank(f.transform) || f.transform == 'None')
                ? f.dataType
                : f.dataType + ' with transform ' + f.transform;
            errors.add('Field Mapping on "' + mappingName + '": Default Value "' + f.defaultValue + '" for ' +
                f.targetField + ' is not a valid ' + how + '.');
        }
    }
```

- [ ] **Step 4: Deploy and run**

```bash
sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/classes --wait 10
sf apex run test --target-org htx-defaults --class-names HumanitixMappingEngineTest,HumanitixDefaultMappingsTest --result-format human --wait 10
```
Expected: all tests **Pass**, including `shippedDefaultsValidateAgainstOrgSchema` (the shipped resource still has no defaults at this point).

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/classes/HumanitixMappingConfig.cls force-app/main/default/classes/HumanitixMappingEngineTest.cls
git commit -m "feat(config): validate fixed default values against the mapping's Data Type"
```

---

### Task 5: Record builder uses the fallbacks (new `HumanitixRecordBuilderTest`)

**Files:**
- Modify: `force-app/main/default/classes/HumanitixRecordBuilder.cls:1-9` (doc), `:64-97` (field loop)
- Create: `force-app/main/default/classes/HumanitixRecordBuilderTest.cls`
- Create: `force-app/main/default/classes/HumanitixRecordBuilderTest.cls-meta.xml`

**Interfaces:**
- Consumes: `HumanitixTypeCoercer.resolve(...)` (Task 3); `HumanitixRelationshipResolver.RefRequest(record, lookupField, targetObject, externalIdField, keyValue)` with public fields of those names.
- Produces: unchanged public API (`contextsFor`, `build`), now honouring `defaultSourcePath` / `defaultValue` for every active field mapping including `Reference`.

- [ ] **Step 1: Write the failing tests**

Create `force-app/main/default/classes/HumanitixRecordBuilderTest.cls-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ApexClass xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>62.0</apiVersion>
    <status>Active</status>
</ApexClass>
```

Create `force-app/main/default/classes/HumanitixRecordBuilderTest.cls`:

```apex
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
        String json
    ) {
        return HumanitixRecordBuilder.contextsFor(om, (List<Object>) JSON.deserializeUntyped('[' + json + ']'));
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
```

- [ ] **Step 2: Deploy and run to verify the fallback tests fail**

```bash
sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/classes --wait 10
sf apex run test --target-org htx-defaults --class-names HumanitixRecordBuilderTest --result-format human --wait 10
```
Expected: deploy `Succeeded`; `defaultValueFillsBlankSourceAndYieldsToPresentValue`, `defaultSourcePathBeatsFixedDefault` and `referenceKeyFallsBackToDefaultPath` **Fail** (`Expected: Unknown, Actual: null` etc.); `noDefaultLeavesBlankBehaviourUnchanged` passes already.

- [ ] **Step 3: Route the builder through `resolve()`**

In `HumanitixRecordBuilder.cls`, replace the doc comment's first paragraph:

```apex
/**
 * Turns deserialized Humanitix JSON records into target SObjects for one Object
 * Mapping, using its Field Mappings. Every field value comes from
 * HumanitixTypeCoercer.resolve, which applies the mapping's Default Source Path
 * and Default Value when the Humanitix value is blank. Non-reference fields are
 * coerced and set inline; reference fields become RefRequests for the
 * RelationshipResolver.
 *
 * Handles nested-collection mappings (e.g. an event's ticketTypes[]) by expanding
 * each array element into its own context, with `$parent`/`$root` pointing at the
 * enclosing record.
 */
```

and replace the body of the `for (HumanitixMappingConfig.FieldMapping f : om.fields)` loop in `build()` with:

```apex
            for (HumanitixMappingConfig.FieldMapping f : om.fields) {
                if (!f.active) {
                    continue;
                }
                // Isolate a single malformed value so it can't abort the whole page;
                // the record keeps the fields that mapped cleanly.
                try {
                    Object value = HumanitixTypeCoercer.resolve(f, c.record, c.parent, c.root);
                    if (f.dataType == 'Reference') {
                        // The (possibly defaulted) value is the external-id key the
                        // resolver matches against Transform Arg's Object.Field.
                        String key = value == null ? null : String.valueOf(value);
                        if (String.isNotBlank(key) && String.isNotBlank(f.transformArg) && f.transformArg.contains('.')) {
                            List<String> parts = f.transformArg.split('\\.');
                            out.refs.add(
                                new HumanitixRelationshipResolver.RefRequest(sob, f.targetField, parts[0], parts[1], key)
                            );
                        }
                        continue;
                    }
                    if (value == null && !f.overwriteBlank) {
                        continue; // leave existing value intact
                    }
                    sob.put(f.targetField, value);
                } catch (Exception e) {
                    // Skip just this field; other fields on the record still map.
                    continue;
                }
            }
```

- [ ] **Step 4: Deploy and run the builder, coercer and engine tests**

```bash
sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/classes --wait 10
sf apex run test --target-org htx-defaults --class-names HumanitixRecordBuilderTest,HumanitixTypeCoercerTest,HumanitixMappingEngineTest,HumanitixPersisterTest --result-format human --wait 20
```
Expected: all **Pass** (4 builder tests, engine end-to-end unchanged).

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/classes/HumanitixRecordBuilder.cls force-app/main/default/classes/HumanitixRecordBuilderTest.cls force-app/main/default/classes/HumanitixRecordBuilderTest.cls-meta.xml
git commit -m "feat(builder): apply field mapping defaults when the Humanitix value is blank"
```

---

### Task 6: Admin controller DTO, queries and save maps carry the defaults

**Files:**
- Modify: `force-app/main/default/classes/HumanitixMappingAdminController.cls:44-56` (DTO), `:126-131` (getFieldMappings SOQL), `:376-379` (effectiveFieldRecordsByName SOQL), `:451-482` (`fieldDtoFromRecord`, `fieldDtoFromDefault`), `:500-512` (`toFieldRecord`), `:529-540` (`fieldValues`)
- Test: `force-app/main/default/classes/HumanitixMappingAdminControllerTest.cls` (append three tests)

**Interfaces:**
- Consumes: `validate()` error text from Task 4 (`Default Value "lots"`), `HumanitixMetadataWriter.lastContainer` (test seam), `HumanitixDefaultMappings.DefaultRecord.values` keyed by CMT field API name.
- Produces: `FieldMappingDto.defaultSourcePath : String` and `FieldMappingDto.defaultValue : String` (`@AuraEnabled`), read by the LWC in Task 7 with exactly those names; deploy payload keys `Default_Source_Path__c` / `Default_Value__c`.

- [ ] **Step 1: Write the failing tests**

Append to `HumanitixMappingAdminControllerTest`:

```apex
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
            // Task 8 ships LastName with Default Value "Unknown"; until then the
            // defaults world reads null. Either value proves the property flows.
            System.assert(lastName.defaultValue == null || lastName.defaultValue == 'Unknown', 'unexpected default: ' + lastName.defaultValue);
        }
    }
```

- [ ] **Step 2: Deploy to verify it fails**

```bash
sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/classes --wait 10
```
Expected: deploy **fails**: `Variable does not exist: defaultSourcePath` on `HumanitixMappingAdminControllerTest`.

- [ ] **Step 3: Carry the two settings through the controller**

In `HumanitixMappingAdminController.cls`:

(a) `FieldMappingDto`: after `@AuraEnabled public String transformArg;` add
```apex
        @AuraEnabled public String defaultSourcePath;
        @AuraEnabled public String defaultValue;
```

(b) `getFieldMappings` SOQL becomes:
```apex
                for (Humanitix_Field_Mapping__mdt fm : [
                    SELECT DeveloperName, MasterLabel, Object_Mapping__c, Source_Path__c, Target_Field__c,
                        Data_Type__c, Transform__c, Transform_Arg__c, Default_Source_Path__c, Default_Value__c,
                        Is_External_Id__c, Overwrite_Blank__c, Is_Active__c
                    FROM Humanitix_Field_Mapping__mdt
                    WHERE Object_Mapping__c = :objectMappingDevName
                    ORDER BY DeveloperName
                ]) {
```

(c) `effectiveFieldRecordsByName` SOQL becomes:
```apex
            for (Humanitix_Field_Mapping__mdt fm : [
                SELECT DeveloperName, Object_Mapping__c, Source_Path__c, Target_Field__c, Data_Type__c,
                    Transform__c, Transform_Arg__c, Default_Source_Path__c, Default_Value__c,
                    Is_External_Id__c, Overwrite_Blank__c, Is_Active__c
                FROM Humanitix_Field_Mapping__mdt
            ]) {
```

(d) `fieldDtoFromRecord`: after `dto.transformArg = fm.Transform_Arg__c;` add
```apex
        dto.defaultSourcePath = fm.Default_Source_Path__c;
        dto.defaultValue = fm.Default_Value__c;
```

(e) `fieldDtoFromDefault`: after `dto.transformArg = (String) r.values.get('Transform_Arg__c');` add
```apex
        dto.defaultSourcePath = (String) r.values.get('Default_Source_Path__c');
        dto.defaultValue = (String) r.values.get('Default_Value__c');
```

(f) `toFieldRecord`: after `Transform_Arg__c = dto.transformArg,` add
```apex
            Default_Source_Path__c = dto.defaultSourcePath,
            Default_Value__c = dto.defaultValue,
```

(g) `fieldValues`: after `'Transform_Arg__c' => dto.transformArg,` add
```apex
            'Default_Source_Path__c' => dto.defaultSourcePath,
            'Default_Value__c' => dto.defaultValue,
```

- [ ] **Step 4: Deploy and run the controller tests**

```bash
sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/classes --wait 10
sf apex run test --target-org htx-defaults --class-names HumanitixMappingAdminControllerTest --result-format human --wait 10
```
Expected: all 14 tests **Pass** (11 existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add force-app/main/default/classes/HumanitixMappingAdminController.cls force-app/main/default/classes/HumanitixMappingAdminControllerTest.cls
git commit -m "feat(admin): round-trip Default Source Path and Default Value through the mapping DTOs"
```

---

### Task 7: Mappings tab editor (LWC + Jest)

**Files:**
- Modify: `force-app/main/default/lwc/humanitixMappingFieldForm/humanitixMappingFieldForm.html:73-81` (after the Transform Arg block)
- Modify: `force-app/main/default/lwc/humanitixMappingFieldForm/humanitixMappingFieldForm.js` (constant, state, `applyMapping`, handlers, `validate`, `buildDto`)
- Modify: `force-app/main/default/lwc/humanitixSetupMappings/humanitixSetupMappings.js:103-117` (`fieldDto`)
- Test: `force-app/main/default/lwc/humanitixMappingFieldForm/__tests__/humanitixMappingFieldForm.test.js`
- Test: `force-app/main/default/lwc/humanitixSetupMappings/__tests__/humanitixSetupMappings.test.js`

**Interfaces:**
- Consumes: `FieldMappingDto.defaultSourcePath` / `defaultValue` (Task 6).
- Produces: the queue event DTO gains `defaultSourcePath` and `defaultValue` (trimmed string or `null`); `fieldDto(row, overrides)` in the tab forwards both keys so a toggle never drops them.

- [ ] **Step 1: Write the failing Jest tests**

In `humanitixMappingFieldForm.test.js`, inside the existing test `'queues a create with a blank devName and the parent mapping'`, after `expect(dto.transformArg).toBeNull();` add:
```js
    expect(dto.defaultSourcePath).toBeNull();
    expect(dto.defaultValue).toBeNull();
```

Then append these tests before the closing `});` of the `describe`:

```js
  it('renders the default inputs and queues them trimmed in the DTO', async () => {
    const element = await create();
    const queued = listenForQueue(element);

    expect(inputByLabel(element, 'Default Source Path')).not.toBeNull();
    expect(inputByLabel(element, 'Default Value')).not.toBeNull();

    setInput(element, 'Source Path', 'organisation');
    chooseCombobox(element, 'Target Field', 'Name');
    setInput(element, 'Default Source Path', ' _id ');
    setInput(element, 'Default Value', ' Unknown ');
    await settle();

    click(element, 'Queue change');
    await settle();

    expect(queued).toHaveBeenCalledTimes(1);
    const dto = queued.mock.calls[0][0].detail;
    expect(dto.defaultSourcePath).toBe('_id');
    expect(dto.defaultValue).toBe('Unknown');
  });

  it('accepts a mapping with no source path when a default is set', async () => {
    const element = await create();
    const queued = listenForQueue(element);

    chooseCombobox(element, 'Target Field', 'Name');
    setInput(element, 'Default Value', 'Unknown');
    await settle();

    click(element, 'Queue change');
    await settle();

    expect(queued).toHaveBeenCalledTimes(1);
    const dto = queued.mock.calls[0][0].detail;
    expect(dto.sourcePath).toBeNull();
    expect(dto.defaultValue).toBe('Unknown');
  });

  it('still blocks a mapping with neither a source path nor a default', async () => {
    const element = await create();
    const queued = listenForQueue(element);

    chooseCombobox(element, 'Target Field', 'Name');
    await settle();

    click(element, 'Queue change');
    await settle();

    expect(queued).not.toHaveBeenCalled();
    expect(text(element)).toContain('Enter a source path');
  });

  it('pre-fills the defaults of an existing mapping', async () => {
    const element = await create({
      mapping: { ...EXISTING, defaultSourcePath: '_id', defaultValue: 'Unknown' }
    });

    expect(inputByLabel(element, 'Default Source Path').value).toBe('_id');
    expect(inputByLabel(element, 'Default Value').value).toBe('Unknown');
  });
```

In `humanitixSetupMappings.test.js`, append before the closing `});` of the `describe`:

```js
  it('keeps the default settings when toggling a field mapping', async () => {
    const element = await createAndLoad();

    rowAction(element, 'view', { ...OBJECT_MAPPINGS[0] });
    await settle();
    rowAction(element, 'toggle', {
      ...FIELD_MAPPINGS[1],
      defaultSourcePath: '_id',
      defaultValue: 'Unknown'
    });
    await settle();

    click(element, 'Save All');
    await settle();

    const payload = JSON.parse(savePending.mock.calls[0][0].pendingJson);
    expect(payload.fieldMappings).toHaveLength(1);
    expect(payload.fieldMappings[0].devName).toBe('Event_to_Event_02');
    expect(payload.fieldMappings[0].active).toBe(false);
    expect(payload.fieldMappings[0].defaultSourcePath).toBe('_id');
    expect(payload.fieldMappings[0].defaultValue).toBe('Unknown');
  });
```

- [ ] **Step 2: Run Jest to verify they fail**

```bash
npx sfdx-lwc-jest
```
Expected: 5 failures out of 55: `'queues a create with a blank devName...'` (`defaultSourcePath` is `undefined`, not `null`), `'renders the default inputs...'` (the Default Source Path input is null), `'accepts a mapping with no source path when a default is set'` (the queue is blocked), `'pre-fills the defaults of an existing mapping'` (input null) and `'keeps the default settings when toggling a field mapping'` (`defaultSourcePath` undefined in the payload). `'still blocks a mapping with neither...'` already passes; that is fine.

- [ ] **Step 3: Implement the form**

In `humanitixMappingFieldForm.html`, directly after the closing `</template>` of the `showTransformArg` block and before the `External Id` checkbox, insert:

```html
        <lightning-input
          type="text"
          label="Default Source Path"
          field-level-help="Another Humanitix path to read when the mapped value is blank, for example _id or $parent.name. Tried before the fixed Default Value."
          value={defaultSourcePath}
          onchange={handleDefaultSourcePathChange}
          class="slds-m-bottom_small"
        ></lightning-input>

        <lightning-input
          type="text"
          label="Default Value"
          field-level-help="Fixed text written when both the mapped value and the Default Source Path are blank. It goes through the same Transform and Data Type as the mapped value."
          value={defaultValue}
          onchange={handleDefaultValueChange}
          class="slds-m-bottom_small"
        ></lightning-input>
```

In `humanitixMappingFieldForm.js`:

(a) Replace the `NO_SOURCE_PATH` constant:
```js
const NO_SOURCE_PATH =
  'Enter a source path, set a Default Source Path or Default Value, or choose the StaticValue transform.';
```

(b) After `transformArg = '';` in the state block add:
```js
  defaultSourcePath = '';
  defaultValue = '';
```

(c) In `applyMapping()`, after `this.transformArg = dto.transformArg || '';` add:
```js
    this.defaultSourcePath = dto.defaultSourcePath || '';
    this.defaultValue = dto.defaultValue || '';
```

(d) After `handleTransformArgChange(event) {...}` add:
```js
  handleDefaultSourcePathChange(event) {
    this.defaultSourcePath = event.target.value;
  }

  handleDefaultValueChange(event) {
    this.defaultValue = event.target.value;
  }
```

(e) In `validate()`, replace
```js
    if (this.transform !== 'StaticValue' && !hasText(this.sourcePath)) {
      problems.push(NO_SOURCE_PATH);
    }
```
with
```js
    const hasSource =
      hasText(this.sourcePath) || hasText(this.defaultSourcePath) || hasText(this.defaultValue);
    if (this.transform !== 'StaticValue' && !hasSource) {
      problems.push(NO_SOURCE_PATH);
    }
```

(f) In `buildDto()`, after `transformArg: trimmedOrNull(this.transformArg),` add:
```js
      defaultSourcePath: trimmedOrNull(this.defaultSourcePath),
      defaultValue: trimmedOrNull(this.defaultValue),
```

In `humanitixSetupMappings.js`, in `fieldDto(row, overrides)`, after `transformArg: row.transformArg,` add:
```js
    defaultSourcePath: row.defaultSourcePath,
    defaultValue: row.defaultValue,
```

- [ ] **Step 4: Run the whole Jest suite**

```bash
npx sfdx-lwc-jest
```
Expected: `Tests: 55 passed, 55 total` (50 + 5).

- [ ] **Step 5: Deploy the LWC to the dev org**

```bash
sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/lwc --wait 10
```
Expected: `Succeeded`.

- [ ] **Step 6: Commit**

```bash
git add force-app/main/default/lwc/humanitixMappingFieldForm/humanitixMappingFieldForm.html force-app/main/default/lwc/humanitixMappingFieldForm/humanitixMappingFieldForm.js force-app/main/default/lwc/humanitixMappingFieldForm/__tests__/humanitixMappingFieldForm.test.js force-app/main/default/lwc/humanitixSetupMappings/humanitixSetupMappings.js force-app/main/default/lwc/humanitixSetupMappings/__tests__/humanitixSetupMappings.test.js
git commit -m "feat(setup): edit Default Source Path and Default Value in the field mapping form"
```

---

### Task 8: Shipped defaults (Lead.Company, Contact.LastName), resource, end-to-end tests

**Files:**
- Modify: `scripts/dev/generate-default-mappings.py:14-27` (docstring), `:65-68` (`fm`), `:171-180` (Order_to_Contact fields), `:302-314` (Order_to_Lead), `:355-368` (`emit_field_mapping`)
- Regenerate: `force-app/main/default/customMetadata/*.md-meta.xml` (Order_to_Contact_03, Order_to_Lead object record, Order_to_Lead_03/06/07 change; `Order_to_Lead_08` is deleted; `Humanitix_Object_Mapping.Order_to_Contact` gets a cosmetic value reorder)
- Regenerate: `force-app/main/default/staticresources/Humanitix_Default_Mappings.json`
- Test: `force-app/main/default/classes/HumanitixMappingEngineTest.cls` (append two tests)

**Interfaces:**
- Consumes: `HumanitixTestDataFactory.orderJson()` (contains `"lastName":"Baggins",`, `"organisation":"Fellowship",`, `"email":"Frodo@Shire.com"`, `"_id":"ord_frodo_1"`), `HumanitixMappingConfig.getInstance().objectMappings` (public list; `active` is public).
- Produces: shipped records `Order_to_Contact_03` (LastName, Default Value `Unknown`), `Order_to_Lead_03` (LastName, Default Value `Unknown`), `Order_to_Lead_06` (Company from `organisation`, Default Value `Unknown`), `Order_to_Lead_07` (Humanitix_Last_Order_Id__c, previously `_08`); 158 field mapping records, 172 records total in the resource.

Note on scope: the spec names `Lead.Company` and `Contact.LastName`. `Lead.LastName` is required in exactly the same way, so it gets the same `Unknown` default here (Order_to_Lead ships inactive, so nothing changes for existing installs). Call this out in the release notes.

- [ ] **Step 1: Write the failing end-to-end tests**

Append to `HumanitixMappingEngineTest`:

```apex
    @IsTest
    static void contactLastNameDefaultsToUnknownWhenTheOrderHasNone() {
        HumanitixTestDataFactory.useShippedMappings();
        List<Object> orders = (List<Object>) JSON.deserializeUntyped(
            '[' + HumanitixTestDataFactory.orderJson().replace('"lastName":"Baggins",', '') + ']'
        );
        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            Test.startTest();
            HumanitixMappingEngine.run('Event', HumanitixTestDataFactory.events());
            HumanitixMappingEngine.run('Order', orders);
            Test.stopTest();
        }
        Contact c = [SELECT LastName FROM Contact WHERE Humanitix_Contact_Key__c = 'frodo@shire.com'];
        System.assertEquals('Unknown', c.LastName, 'the shipped Contact.LastName default must fill a missing last name');
    }

    @IsTest
    static void leadCompanyUsesOrganisationOrDefaultsToUnknown() {
        HumanitixTestDataFactory.useShippedMappings();
        for (HumanitixMappingConfig.ObjectMapping om : HumanitixMappingConfig.getInstance().objectMappings) {
            if (om.devName == 'Order_to_Lead') {
                om.active = true; // ships inactive; the fixture flips it on in memory only
            }
        }
        String withOrg = HumanitixTestDataFactory.orderJson();
        String withoutOrg = withOrg
            .replace('"organisation":"Fellowship",', '')
            .replace('"email":"Frodo@Shire.com"', '"email":"Sam@Shire.com"')
            .replace('"_id":"' + HumanitixTestDataFactory.ORDER_ID + '"', '"_id":"ord_sam_1"');
        List<Object> orders = (List<Object>) JSON.deserializeUntyped('[' + withOrg + ',' + withoutOrg + ']');

        System.runAs(HumanitixTestDataFactory.marketingAdmin()) {
            Test.startTest();
            HumanitixMappingEngine.run('Event', HumanitixTestDataFactory.events());
            HumanitixMappingEngine.run('Order', orders);
            Test.stopTest();
        }

        Map<String, Lead> byKey = new Map<String, Lead>();
        for (Lead l : [
            SELECT Company, Humanitix_Contact_Key__c
            FROM Lead
            WHERE Humanitix_Contact_Key__c IN ('frodo@shire.com', 'sam@shire.com')
        ]) {
            byKey.put(l.Humanitix_Contact_Key__c, l);
        }
        System.assertEquals(2, byKey.size(), 'both orders must produce a Lead');
        System.assertEquals('Fellowship', byKey.get('frodo@shire.com').Company, 'a present organisation wins');
        System.assertEquals('Unknown', byKey.get('sam@shire.com').Company, 'a missing organisation falls back to the shipped default');
    }
```

- [ ] **Step 2: Deploy and run to verify they fail**

```bash
sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/classes --wait 10
sf apex run test --target-org htx-defaults --class-names HumanitixMappingEngineTest --result-format human --wait 20
```
Expected: `contactLastNameDefaultsToUnknownWhenTheOrderHasNone` **Fail** (`List has no rows for assignment to SObject`: the Contact insert failed on the required LastName). `leadCompanyUsesOrganisationOrDefaultsToUnknown` **Fail** on `a present organisation wins` (`Expected: Fellowship, Actual: Unknown`): the current shipped pair evaluates `organisation` and then the StaticValue row in developer-name order, so the StaticValue overwrites Frodo's organisation.

- [ ] **Step 3: Update the generator (source of truth)**

In `scripts/dev/generate-default-mappings.py`:

(a) In the module docstring's "Contract encoded here" list, after the DecimalMoney bullet, add:
```
  - Default_Source_Path / Default_Value are fallbacks evaluated after the
    Transform when the mapped value is blank: the default path first, then the
    fixed value; the winner goes through the same Transform and Data Type.
```

(b) Replace `fm()`:
```python
def fm(source, target, dtype="Text", transform="None", arg=None,
       extid=False, overwrite=True, active=True, default_path=None, default_value=None):
    return dict(source=source, target=target, dtype=dtype, transform=transform,
                arg=arg, extid=extid, overwrite=overwrite, active=active,
                default_path=default_path, default_value=default_value)
```

(c) Order_to_Contact fields: change `fm("firstName", "FirstName"), fm("lastName", "LastName"),` to
```python
        fm("firstName", "FirstName"), fm("lastName", "LastName", default_value="Unknown"),
```

(d) Order_to_Lead becomes:
```python
# L) Order -> Lead (OPTIONAL, inactive by default)
MAPPINGS.append(om(
    "Order_to_Lead", "Order to Lead (optional)", "Order", "Lead",
    ext_id_field="Humanitix_Contact_Key__c", load=30, active=False,
    description="OPTIONAL: activate to route buyers to Leads instead of / as well as Contacts. "
                "Lead.Company and Lead.LastName are required, so they default to Unknown when the order has no value.",
    fields=[
        fm("email", "Humanitix_Contact_Key__c", "Text", "Lower", extid=True),
        fm("firstName", "FirstName"), fm("lastName", "LastName", default_value="Unknown"),
        fm("email", "Email", "Email", "Lower"), fm("mobile", "MobilePhone", "Phone"),
        fm("organisation", "Company", default_value="Unknown"),
        fm("_id", "Humanitix_Last_Order_Id__c"),
    ]))
```

(e) In `emit_field_mapping`, after the `Transform_Arg__c` append add:
```python
    if f.get("default_path"):
        rows.append(val("Default_Source_Path__c", f["default_path"], "string"))
    if f.get("default_value") is not None:
        rows.append(val("Default_Value__c", f["default_value"], "string"))
```

- [ ] **Step 4: Regenerate records, delete the stale one, regenerate the resource**

```bash
python3 scripts/dev/generate-default-mappings.py
git rm --quiet force-app/main/default/customMetadata/Humanitix_Field_Mapping.Order_to_Lead_08.md-meta.xml
python3 scripts/dev/generate-mappings-resource.py
git status --short
```
Expected output lines: `Generated 13 object mappings, 158 field mappings, 1 sync setting`, then `Humanitix_Field_Mapping: 158`, `Humanitix_Object_Mapping: 13`, `Humanitix_Sync_Setting: 1`. `git status` shows modified `Order_to_Contact_03`, `Humanitix_Object_Mapping.Order_to_Contact` (value reorder only), `Humanitix_Object_Mapping.Order_to_Lead`, `Order_to_Lead_03`, `Order_to_Lead_06`, `Order_to_Lead_07`, the deleted `Order_to_Lead_08`, the resource JSON and the generator.

Sanity-check the resource:
```bash
python3 -c "
import json
d = json.load(open('force-app/main/default/staticresources/Humanitix_Default_Mappings.json'))
by = {(r['type'], r['developerName']): r['values'] for r in d['records']}
print(len(d['records']), 'records')
print(by[('Humanitix_Field_Mapping', 'Order_to_Contact_03')])
print(by[('Humanitix_Field_Mapping', 'Order_to_Lead_06')])
print(by[('Humanitix_Field_Mapping', 'Order_to_Lead_07')])
assert ('Humanitix_Field_Mapping', 'Order_to_Lead_08') not in by
"
```
Expected: `172 records`; `Order_to_Contact_03` has `'Default_Value__c': 'Unknown'` and `'Target_Field__c': 'LastName'`; `Order_to_Lead_06` has `'Source_Path__c': 'organisation'`, `'Target_Field__c': 'Company'`, `'Default_Value__c': 'Unknown'`, `'Transform__c': 'None'`; `Order_to_Lead_07` targets `Humanitix_Last_Order_Id__c`.

- [ ] **Step 5: Deploy the resource and classes, run the engine tests**

```bash
sf project deploy start --target-org htx-defaults --source-dir force-app/main/default/staticresources --source-dir force-app/main/default/classes --wait 10
sf apex run test --target-org htx-defaults --class-names HumanitixMappingEngineTest,HumanitixDefaultMappingsTest,HumanitixMappingSeederTest,HumanitixMappingAdminControllerTest --result-format human --wait 20
```
Expected: all **Pass**, including the two new end-to-end tests and `shippedDefaultsValidateAgainstOrgSchema`.

- [ ] **Step 6: Seed the dev org from the new resource**

```bash
echo "System.enqueueJob(new HumanitixMappingSeeder());" | sf apex run --target-org htx-defaults
```
The seeding deployment is asynchronous; wait about a minute, then:
```bash
sf data query --target-org htx-defaults --query "SELECT COUNT() FROM Humanitix_Field_Mapping__mdt"
sf data query --target-org htx-defaults --query "SELECT DeveloperName, Target_Field__c, Default_Value__c FROM Humanitix_Field_Mapping__mdt WHERE Default_Value__c != null ORDER BY DeveloperName"
```
Expected: 158 field mappings; three rows (`Order_to_Contact_03` LastName, `Order_to_Lead_03` LastName, `Order_to_Lead_06` Company), each `Unknown`. If the count is still 0, wait another minute and re-query (the deployment is async).

- [ ] **Step 7: Commit**

```bash
git add scripts/dev/generate-default-mappings.py force-app/main/default/customMetadata force-app/main/default/staticresources/Humanitix_Default_Mappings.json force-app/main/default/classes/HumanitixMappingEngineTest.cls
git commit -m "feat(defaults): ship Unknown defaults for Contact.LastName and Lead.Company; drop the StaticValue duplicate"
```
(`git add force-app/main/default/customMetadata` stages the modified and deleted record files; confirm with `git status --short` that nothing outside the listed paths is staged.)

---

### Task 9: Docs and version bump

**Files:**
- Modify: `docs/FIELD-MAPPING.md` (editor bullet, field table, new "Defaults" section, recipe)
- Modify: `README.md:33` ("What it does" bullet)
- Modify: `sfdx-project.json:6-7`

- [ ] **Step 1: FIELD-MAPPING.md, editor bullet**

Replace the bullet
```markdown
- **Edit or create a field mapping.** The target field comes from a picker of the
  writable fields on that mapping's target object, so an API name can't be
  mistyped.
```
with
```markdown
- **Edit or create a field mapping.** The target field comes from a picker of the
  writable fields on that mapping's target object, so an API name can't be
  mistyped. Each field mapping can also carry a Default Source Path and a Default
  Value (see [Defaults](#defaults) below).
```

- [ ] **Step 2: FIELD-MAPPING.md, field table rows**

After the `| Transform Arg | ... |` row insert:
```markdown
| Default Source Path | Another Humanitix path to read when the mapped value is blank, e.g. `_id` or `$parent.name`. Tried before Default Value. |
| Default Value | Fixed text used when the mapped value and the Default Source Path are both blank, e.g. `Unknown` for a required field. |
```

- [ ] **Step 3: FIELD-MAPPING.md, Defaults section**

Insert after the "### References (lookups)" paragraph (before "## Update modes"):

```markdown
### Defaults

Required Salesforce fields are the usual reason a record fails to insert:
`Lead.Company` and `Contact.LastName` are required, and Humanitix does not always
have a value for them. A field mapping can carry two fallbacks so the connector
still writes something sensible:

1. The Humanitix value at **Source Path** is used when it is present.
2. Otherwise the value at **Default Source Path** is used, if that is present.
3. Otherwise the fixed **Default Value** is used, if one is set.

"Present" is judged after the Transform runs and before the value is coerced to
the Data Type, so a `Trim` or `JoinArray` result of an empty string also falls
through to the defaults. Whichever value wins then goes through the mapping's
Transform and Data Type like any other value: a Default Value of `true` on a
`Boolean` field ticks the box, and a Default Value of `abc` on a `Decimal` field
is reported by validation before the run starts. A `Reference` mapping applies
the same fallbacks to the external id it resolves. `StaticValue` ignores both
defaults; a mapping with no Source Path and only a Default Value is the simpler
way to write a constant.

Defaults follow the object mapping's Update Mode. Under `Always`, a default is
written whenever Humanitix sends a blank, which can replace a value someone typed
into Salesforce, exactly as `Overwrite With Blank` lets a blank clear a field.
Use `BlanksOnly` on mappings that touch curated records (the shipped Order to
Contact mapping already does).

The shipped mappings use this for `Contact.LastName` (Source Path `lastName`,
Default Value `Unknown`) and, on the optional Lead mapping, `Lead.Company`
(Source Path `organisation`, Default Value `Unknown`) and `Lead.LastName`. Orgs
that installed an earlier version keep their existing records; add a default to
your own mapping records from the Mappings tab.
```

- [ ] **Step 4: FIELD-MAPPING.md, recipe**

In "## Recipes", after the "Repoint a field." paragraph insert:
```markdown
**Default an external id to the Humanitix record id.** On the field mapping that
populates your external id, set Source Path to the field you prefer and Default
Source Path to `_id`, so the Humanitix id fills in whenever the preferred field is
blank.
```

- [ ] **Step 5: README bullet**

After the "**Repoint any field**" bullet in "## What it does" insert:
```markdown
- **Default values** for any target field: fall back to another Humanitix field or a fixed value when the source is blank, so required fields such as `Contact.LastName` and `Lead.Company` still get a value.
```

- [ ] **Step 6: Version bump**

In `sfdx-project.json` set:
```json
      "versionName": "Version 1.2",
      "versionNumber": "1.2.0.NEXT",
```

- [ ] **Step 7: Check for em dashes in the touched user-facing files, then commit**

```bash
git diff -U0 -- docs/FIELD-MAPPING.md README.md | grep '^+' | grep -c '—' || true
```
Expected: `0` (only pre-existing em dashes remain in the files; none added).

```bash
git add docs/FIELD-MAPPING.md README.md sfdx-project.json
git commit -m "docs: document field mapping defaults; bump package to 1.2.0.NEXT"
```

---

### Task 10: Full regression and in-app walkthrough

**Files:** none modified (verification only; fix and re-run if anything fails).

- [ ] **Step 1: Apex, full suite with coverage**

```bash
sf project deploy start --target-org htx-defaults --wait 30
sf apex run test --target-org htx-defaults --test-level RunLocalTests --code-coverage --result-format human --wait 30
```
Expected: `Outcome: Passed`, 157 tests (139 baseline + 1 in Task 2 + 7 in Task 3 + 1 in Task 4 + 4 in Task 5 + 3 in Task 6 + 2 in Task 8) and org-wide coverage well above 75%. Record both numbers as printed for the release notes.

- [ ] **Step 2: Jest**

```bash
npx sfdx-lwc-jest
```
Expected: `Tests: 55 passed, 55 total`.

- [ ] **Step 3: Walkthrough in the dev org (browser)**

```bash
sf org open --target-org htx-defaults --path /lightning/n/Humanitix_Setup --url-only
```
Open the printed URL in the browser pane and check, taking a screenshot at each stop:
1. Mappings tab, no "shipped defaults" banner (the org is seeded), open **Order to Contact (buyer)** > View fields > **LastName** > Edit: the form shows **Default Source Path** (blank) and **Default Value** `Unknown` pre-filled with help bubbles.
2. Change Default Value to `Unknown` + a space, Queue change, then **Validate**: no problems. **Save All**: the deploy status resolves to Succeeded and the row reloads.
3. New Field Mapping on Order to Humanitix Order: Target Field `Total__c`, Data Type `Decimal`, Default Value `abc`, Queue change, **Validate**: the problem list shows `Default Value "abc" for Total__c is not a valid Decimal.` Discard.
4. New Field Mapping with no Source Path and no defaults: the form blocks it with the "Enter a source path, set a Default Source Path or Default Value, or choose the StaticValue transform." message.

Then confirm the save landed:
```bash
sf data query --target-org htx-defaults --query "SELECT Default_Value__c, Default_Source_Path__c FROM Humanitix_Field_Mapping__mdt WHERE DeveloperName = 'Order_to_Contact_03'"
```
Expected: `Unknown` (trimmed) and null.

If any step fails, fix it in the relevant task's files with a test, re-run Steps 1 to 3, and commit with an explicit path list.

---

### Task 11: Package 1.2.0: build, install-test, promote, release

**Files:**
- Modify (by the CLI): `sfdx-project.json` (`packageAliases` gains `Humanitix Salesforce Connector@1.2.0-1`)
- Modify: `README.md`, `docs/INSTALL.md`, `docs/PUBLISHING.md` (04t id swap; version text 1.1.0 to 1.2.0 in README and INSTALL)

- [ ] **Step 1: Confirm a clean tree and push the branch**

```bash
git status --short
git push -u origin HEAD
```
Expected: no output from status; branch pushed.

- [ ] **Step 2: Create the version**

```bash
sf package version create --package "Humanitix Salesforce Connector" --installation-key-bypass --code-coverage --wait 90 --target-dev-hub SAASKOOLProd
```
Expected: `Successfully created the package version [08c...]. Subscriber Package Version Id: 04t...` and `sfdx-project.json` gains the alias `Humanitix Salesforce Connector@1.2.0-1`. Note the 04t id: every later command in Tasks 11 and 12 writes `NEW_04T` where that literal id goes; substitute it. If the create fails fast, re-check the two known quirks first (build def must have no edition; no postInstallScript) before debugging package contents.

```bash
git add sfdx-project.json
git commit -m "chore: package version 1.2.0-1"
```

- [ ] **Step 3: Install-test in a fresh scratch org**

```bash
sf org create scratch --definition-file config/project-scratch-def.json --alias insttest --duration-days 1 --wait 10 --target-dev-hub SAASKOOLProd
sf package install --package NEW_04T --target-org insttest --wait 20 --no-prompt
sf org assign permset --name Humanitix_Integration_Admin --target-org insttest
sf apex run test --target-org insttest --test-level RunLocalTests --code-coverage --result-format human --wait 30
sf data query --target-org insttest --query "SELECT COUNT() FROM Humanitix_Field_Mapping__mdt"
sf org delete scratch --target-org insttest --no-prompt
```
Expected: install `Succeeded`; the same test count as Task 10 with `Outcome: Passed` in a record-less org (the shipped-defaults fallback world); the count query returns 0 (records seed lazily on first Setup tab load, unchanged behaviour). Record the numbers.

- [ ] **Step 4: Promote**

```bash
sf package version promote --package NEW_04T --target-dev-hub SAASKOOLProd --no-prompt
sf package version list --target-dev-hub SAASKOOLProd --released
```
Expected: `Successfully promoted the package version`; the list shows 1.2.0.1 with Released true.

- [ ] **Step 5: Swap the install ids and version text**

```bash
grep -rl 04tOb000002IV2bIAG README.md docs/ | xargs sed -i '' "s/04tOb000002IV2bIAG/NEW_04T/g"
sed -i '' 's/Current version: \*\*1.1.0\*\*/Current version: **1.2.0**/' README.md
sed -i '' 's/^Version 1.1.0 (/Version 1.2.0 (/' docs/INSTALL.md
grep -rn "NEW_04T\|1\.2\.0" README.md docs/INSTALL.md docs/PUBLISHING.md
```
Expected: the two install buttons and the `sf package install` line in README and INSTALL, plus the example command in PUBLISHING, all carry the new id; README says `Current version: **1.2.0**`; INSTALL says `Version 1.2.0 (`.

```bash
git add README.md docs/INSTALL.md docs/PUBLISHING.md
git commit -m "docs: point install links at v1.2.0-1"
git push
```

- [ ] **Step 6: Pull request and merge to main**

```bash
gh pr create --base main --title "Field mapping default values (v1.2.0)" --body-file - <<'EOF'
Adds Default Source Path and Default Value to Humanitix field mappings (evaluated after the Transform when the value is blank; precedence Humanitix value, default path, fixed value; same Transform and Data Type; Update Mode unchanged), the Mappings tab inputs, validation of uncoercible defaults, and shipped defaults for Contact.LastName and Lead.Company / Lead.LastName (the StaticValue duplicate on Lead.Company is removed for new installs).

Package 1.2.0-1 built with coverage, install-tested in a fresh scratch org and promoted. Spec: docs/dev/specs/2026-08-19-default-values-design.md. Plan: docs/dev/plans/2026-08-19-field-mapping-default-values.md.
EOF
gh pr checks --watch || true   # returns once the ~2 minute PR Validation run finishes
gh pr merge --rebase --delete-branch
```
Expected: the PR Validation run passes Jest and fails at "Authenticate Dev Hub" (the repo still has no `DEVHUB_SFDX_URL` secret, a known gap); merge with `--rebase` (add `--admin` only if the failing check blocks the merge, as for PR #1). Then in the main checkout:

```bash
cd "/Users/avinashvatsya/Documents/Repos/Salesforce Humanitix Integration" && git checkout main && git pull --ff-only && git log --oneline -3
```

- [ ] **Step 7: GitHub release**

Write the notes with the real numbers from Tasks 10 and 11 (do not invent counts), no em dashes:

```bash
gh release create v1.2.0-1 --target main --title "v1.2.0-1: Field mapping default values" --notes-file - <<'EOF'
## Humanitix Salesforce Connector v1.2.0-1

Field mappings can now carry defaults, so required Salesforce fields get a value even when Humanitix has none.

### New: Default Source Path and Default Value

- Every field mapping has two new settings. When the mapped Humanitix value is blank, the connector reads the **Default Source Path** (another Humanitix field, for example `_id` or `$parent.name`) and, if that is blank too, writes the fixed **Default Value**.
- Blankness is judged after the mapping's Transform and before its Data Type coercion, so a trimmed empty string falls back and a Boolean default is honoured. The winning value goes through the same Transform and Data Type as any other value; `Reference` mappings apply the fallback to the external id they resolve. `StaticValue` is unchanged.
- Validation reports a Default Value the Data Type cannot coerce (for example `abc` on a Decimal field) before a run starts, and before a save from the Mappings tab.
- The Mappings tab field form has both inputs with help text; a mapping needs a Source Path, a default, or the StaticValue transform.
- Update Mode governs updates as before: under `Always` a default can replace an existing value when Humanitix sends blank, exactly as Overwrite With Blank lets a blank clear a field. Use `BlanksOnly` for curated records.

### Shipped defaults (new installs)

- `Contact.LastName` defaults to `Unknown`.
- On the optional Order to Lead mapping, `Lead.Company` is now a single mapping from `organisation` with default `Unknown` (the order-dependent StaticValue duplicate is gone) and `Lead.LastName` defaults to `Unknown`.
- Existing orgs keep their own mapping records; add defaults from the Mappings tab.

### Upgrading

Install over v1.1.0-1 normally. Two Custom Metadata fields are added; nothing else changes shape.

Verified with N passing Apex tests (M% coverage) in a fresh install-test org and 55 passing LWC Jest tests.
EOF
```
Replace `N` and `M` with the numbers printed in Task 11 Step 3 before running. Expected: release published at `https://github.com/avinashvatsya/humanitix-salesforce-connector/releases/tag/v1.2.0-1` (the Release Package workflow will fail on the missing secret, as it did for v1.1.0-1; that is cosmetic).

---

### Task 12: Kaipatiki upgrade, LastName default, green sync

**Files:** none in the repo (memory files updated at the end).

- [ ] **Step 1: Pre-flight**

```bash
sf package installed list --target-org KaipatikiProd
sf data query --target-org KaipatikiProd --query "SELECT COUNT() FROM Humanitix_Object_Mapping__mdt"
sf data query --target-org KaipatikiProd --query "SELECT DeveloperName, Match_Strategy__c, Match_Field_Set__c, Update_Mode__c FROM Humanitix_Object_Mapping__mdt WHERE DeveloperName = 'Order_to_Contact'"
sf data query --target-org KaipatikiProd --query "SELECT Id, Status__c FROM Humanitix_Sync_Log__c WHERE Status__c = 'Running'"
```
Expected: 1.1.0.1 installed; 13 mappings; `MatchByFields | Email | BlanksOnly`; no Running run.

- [ ] **Step 2: Upgrade**

```bash
sf package install --package NEW_04T --target-org KaipatikiProd --wait 20 --security-type AdminsOnly --no-prompt
sf package installed list --target-org KaipatikiProd
sf data query --target-org KaipatikiProd --query "SELECT COUNT() FROM Humanitix_Object_Mapping__mdt"
sf data query --target-org KaipatikiProd --query "SELECT DeveloperName, Match_Strategy__c, Match_Field_Set__c, Update_Mode__c FROM Humanitix_Object_Mapping__mdt WHERE DeveloperName = 'Order_to_Contact'"
sf data query --target-org KaipatikiProd --query "SELECT DeveloperName, Default_Value__c, Default_Source_Path__c FROM Humanitix_Field_Mapping__mdt WHERE DeveloperName = 'Order_to_Contact_03'"
```
Expected: 1.2.0.1 installed; still 13 mappings; BlanksOnly intact; `Order_to_Contact_03` has null defaults (existing records untouched, as designed).

- [ ] **Step 3: Set the Contact.LastName default through the Mappings tab**

```bash
sf org open --target-org KaipatikiProd --path /lightning/n/Humanitix_Setup --url-only
```
In the browser pane: Mappings tab > **Order to Contact (buyer)** > View fields > **LastName** > Edit > Default Value `Unknown` > Queue change > Save All; wait for the deploy status to report success. Then:

```bash
sf data query --target-org KaipatikiProd --query "SELECT DeveloperName, Default_Value__c FROM Humanitix_Field_Mapping__mdt WHERE DeveloperName = 'Order_to_Contact_03'"
```
Expected: `Unknown`.

- [ ] **Step 4: Manual sync, confirm green**

From the Dashboard tab click **Run Sync Now** (or `echo "HumanitixSyncLauncher.start('Manual');" | sf apex run --target-org KaipatikiProd`), then poll:

```bash
sf data query --target-org KaipatikiProd --query "SELECT Name, Status__c, Total_Pages__c, Total_Records_Processed__c, Total_Records_Failed__c, Total_Errors__c, Total_Retries__c, Error_Summary__c FROM Humanitix_Sync_Log__c ORDER BY CreatedDate DESC LIMIT 1"
```
Expected within a few minutes: `Status__c = Success`, `Total_Records_Failed__c = 0`, `Total_Errors__c = 0`. Record the numbers.

- [ ] **Step 5: Update memory**

Update `humanitix-package-status.md` (v1.2.0-1 id, promoted, released, installed in Kaipatiki), `kaipatiki-pilot-status.md` (upgraded, LastName default set, sync numbers), `connector-improvement-roadmap.md` (default values shipped; next is lean mode) and `humanitix-cto-relationship.md` (feature is live; tell the CTO), and the `MEMORY.md` index lines.

---

## Execution notes and review outcome (2026-08-19)

Deviations from the plan as written, all applied on the branch before the package build:

- Task 5: the test helper's `String json` parameter shadowed the `JSON` class (Apex is case-insensitive); renamed to `body`.
- Task 8: the retired `StaticValue` row on `Lead.Company` is **kept as `Order_to_Lead_07` and shipped inactive** instead of deleted, so `Humanitix_Last_Order_Id__c` stays `Order_to_Lead_08` and no shipped DeveloperName changes meaning across upgrades. The resource therefore still holds 159 field mappings / 173 records. The generator docstring now states the rule (never remove or reorder a shipped `fm()` entry; deactivate it).
- Review fixes (code review over the branch diff, 16 candidates verified, 11 kept):
  - `HumanitixPersister.blanksOnlyUpdate` treats an existing value equal to the mapping's own Default Value as blank (a connector placeholder), so a later real value replaces it under `BlanksOnly`; curated values are still never overwritten. Covered by `HumanitixPersisterTest.blanksOnlyReplacesConnectorPlaceholdersButNotCuratedValues` and the second run in `HumanitixMappingEngineTest.contactLastNameDefaultsToUnknownWhenTheOrderHasNone`.
  - `HumanitixMappingConfig.validate()` dry-runs the mapping's constant only (`validateConstantValue`): the `StaticValue` literal, or otherwise the Default Value, never the default path. Fixes a misattributed message for `StaticValue` mappings and a false failure for a `$root` default path; a bad `StaticValue` literal is now reported too.
  - `HumanitixMappingConfig.fromRecords` trims Source Path, Default Source Path and Default Value (`trimToNull`), so records edited in Setup behave like ones saved from the form.
  - `HumanitixMappingAdminController.structuralProblems` rejects a `StaticValue` mapping without a literal, or with defaults set (they would be ignored). The field form hides the default inputs for `StaticValue`, sends nulls for them, requires the literal, and caps the four text inputs at 255 characters.
  - `HumanitixTypeCoercer.resolve` no longer maps `Reference` to `Text` (coerceType already does); it still withholds the Transform Arg for `Reference` mappings.
  - Docs: the Defaults section names the Overwrite With Blank interplay (`= true` qualifier restored), the BlanksOnly placeholder rule, the retired inactive Lead row, and the upgrade steps for 1.1 orgs; the frequency claim in its first sentence was reworded as a mechanism.
- Final counts before the build: 160 Apex tests, 86% org-wide coverage, 56 Jest tests.
