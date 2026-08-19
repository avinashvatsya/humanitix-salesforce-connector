# Field Mapping Default Values — Design

**Date:** 2026-08-19
**Status:** Approved 2026-08-19 (decisions and Approach A engine semantics
confirmed by Avinash; Kaipatiki gets the Contact.LastName default set through
the Mappings tab after the upgrade). Requested by the Humanitix CTO (call the
week before 2026-08-19); the follow-up email commits to it "in the next
release".

## Context and goal

A field mapping today writes exactly what the Humanitix payload holds. When the
payload has no value and the Salesforce field is required, the insert fails
(`REQUIRED_FIELD_MISSING`), and the record is logged as failed. The shipped
mappings already work around this for `Lead.Company` with two mappings on the
same target (`organisation` plus a `StaticValue "Unknown"`), which is
order-dependent. `Contact.LastName` has no fallback at all.

**Goal:** for any target field, especially required ones, an admin can set a
fixed default value, map the field from any Humanitix field, or both: the
Humanitix value is used when present and the default fills in when it is
blank. Configurable from the Mappings tab of the Humanitix Setup console.

### Decisions (confirmed 2026-08-19)

- **Fallback types: fixed value OR another Humanitix field.** Two settings on
  a field mapping. Order of precedence: Humanitix value, then Default Source
  Path, then Default Value.
- **Shipped defaults use it straight away** (new installs only; existing org
  records stay authoritative): `Lead.Company` becomes one mapping
  (`organisation`, Default Value `Unknown`) and the StaticValue duplicate is
  removed; `Contact.LastName` gets Default Value `Unknown`.
- **Release scope:** code, tests, docs, package version **1.2.0** (1.1.0 is
  promoted so `1.1.0.NEXT` is frozen), promote, GitHub release, README/INSTALL
  ids, then upgrade Kaipatiki prod and run a green manual sync.

## Approaches considered

- **A. Two new settings on the field mapping (recommended).**
  `Default_Source_Path__c` and `Default_Value__c` on
  `Humanitix_Field_Mapping__mdt`, evaluated by the record builder. Clean,
  discoverable, no new syntax.
- **B. New transforms (`DefaultIfBlank`, `PathIfBlank`).** No schema change,
  but a mapping has one transform slot, so a default could not be combined
  with `Lower` or `IsoToDateInTz`, and path + fixed fallbacks could not
  coexist. Rejected.
- **C. A plus "fill-only" protection.** Defaulted values would never overwrite
  an existing populated field even in `Always` mode. Needs the builder to
  report defaulted fields and the persister to pre-query on the upsert path
  (one extra SOQL per page). Deferred: `BlanksOnly` mode already protects
  where it matters (Contacts), and C can be added later without a schema
  change.

## Design (Approach A)

### Data model

Two Text(255) fields on `Humanitix_Field_Mapping__mdt`, generated through
`scripts/dev/generate-metadata.py` (`CMTS["Humanitix_Field_Mapping__mdt"]`)
so the XML matches the existing fields:

| Field | Label | Meaning |
| --- | --- | --- |
| `Default_Source_Path__c` | Default Source Path | Humanitix path tried when the mapped value is blank, e.g. `_id`, `email`, `$parent.name` |
| `Default_Value__c` | Default Value | Fixed text used when both the mapped value and the default path are blank |

### Engine

- `HumanitixMappingConfig.FieldMapping` gains `defaultSourcePath` and
  `defaultValue`; `load()` SOQL and `fromRecords()` carry them.
- Evaluation, in `HumanitixRecordBuilder` via `HumanitixTypeCoercer`: run the
  Transform on the Humanitix value; if the result is blank (null or
  whitespace-only string), run the same Transform on the value at the default
  path; if still blank, run it on the fixed default. Then apply the Data Type
  coercion once. Blankness is judged after the Transform and before type
  coercion, so `Trim`/`JoinArray` results of "" trigger the default and a
  Boolean default works (null does not silently become `false` first).
- The chosen value then goes through the unchanged `Overwrite With Blank`
  check and the object mapping's Update Mode. A default is simply "what the
  connector writes when Humanitix has nothing"; whether an existing record is
  touched at all is still `Always` / `BlanksOnly` / `Never`. Documented
  caveat: under `Always`, a default can overwrite an existing value when
  Humanitix later sends blank, exactly as `Overwrite With Blank = true`
  already lets a blank clear it. Use `BlanksOnly` to protect curated records.
- `Reference` data type: the same fallback feeds the external-id key passed
  to `HumanitixRelationshipResolver`.
- `StaticValue` keeps working unchanged (it still short-circuits) but is no
  longer needed; a mapping with no Source Path and only a Default Value is
  the clean way to express a constant.
- `validate()`: if a fixed default is set, dry-run Transform + coercion
  against an empty record inside try/catch and report
  `Default value "abc" is not a valid Decimal` so a typo fails fast before
  DML, matching the existing fail-fast contract.

### Editor (Mappings tab)

- `humanitixMappingFieldForm`: two new inputs after Transform Arg, "Default
  Source Path" and "Default Value", with field-level help. The "source path
  required" rule becomes: Source Path, or StaticValue, or a default.
- `HumanitixMappingAdminController.FieldMappingDto` gains both fields; the two
  SOQL queries, `fieldDtoFromRecord`, `fieldDtoFromDefault`, `toFieldRecord`
  and `fieldValues` carry them so runtime CMDT saves via
  `HumanitixMetadataWriter` round-trip.
- Mappings table unchanged (no new column).

### Shipped defaults

- Edit `scripts/dev/generate-default-mappings.py` (source of truth):
  `fm()` gains `default_path` / `default_value` parameters; Order_to_Lead
  `Company` becomes `fm("organisation", "Company", default_value="Unknown")`
  and the StaticValue row is dropped; Order_to_Contact `LastName` gets
  `default_value="Unknown"`.
- Re-run `generate-default-mappings.py`, then
  `generate-mappings-resource.py` so the `Humanitix_Default_Mappings` static
  resource matches. Record count drops by one; check any test that asserts
  counts.
- Existing orgs keep their records. For Kaipatiki, set the LastName default
  through the Mappings tab after the upgrade (also demonstrates runtime saves).

### Docs

`docs/FIELD-MAPPING.md`: two table rows plus a "Defaults" section including
the Update Mode caveat. README "What it does": one bullet. Keep the
StaticValue transform documented for existing records.

### Tests

- Apex: precedence (value, path, fixed); blank-after-transform; transform
  applied to the default; Boolean and Reference cases; no-default behaviour
  unchanged; config load/fromRecords round-trip; `validate()` rejects a bad
  fixed default; controller DTO round-trip; default-mappings/seeder tests
  pass with the new record set.
- Jest: field form renders both inputs, the relaxed source-path rule, and
  the DTO includes both fields.

### Release

Bump `sfdx-project.json` to `1.2.0.NEXT` ("Version 1.2"). Build with
`--code-coverage`, install-test in a fresh scratch org, promote, swap ids in
README/INSTALL, publish GitHub release v1.2.0-1, `sf package install` into
KaipatikiProd, verify the 13 mappings and BlanksOnly survive, run a manual
sync and confirm it is green. Then tell the Humanitix CTO it is live.

## Constraints and conventions

- No em dashes in any user-facing text (help text, docs, README).
- Commits authored solely by Avinash Vatsya; no Claude co-author trailer.
- CustomMetadata records still cannot deploy directly (platform gack); the
  static resource + seeder path is the only distribution channel.
