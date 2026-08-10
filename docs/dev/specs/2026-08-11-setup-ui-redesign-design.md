# Humanitix Setup Multi-Tab Admin UI — Design

**Date:** 2026-08-11
**Status:** Approved. Supersedes the single-card setup panel; delivers the roadmap's
in-app API key entry + connection check, plus in-app settings, scheduling, and a
full mapping editor.

## Context and goal

Today the *Humanitix Setup* tab is one LWC card (`humanitixSyncAdmin`): Run Sync
Now, Refresh, and the last 25 run rows. Everything an admin actually configures
lives outside the app in Salesforce Setup — the API key on the External
Credential principal, the sync settings on `Humanitix_Sync_Setting__mdt`,
scheduling via anonymous Apex, and 13 object + 159 field mapping CMT records
edited by hand.

**Goal:** make the connector configurable end-to-end from the Setup tab. Five
tabs: **Dashboard**, **Connection**, **Sync Settings**, **Schedule**,
**Mappings**.

### Decisions

- **Daily run = forced full sync; interval runs = forced delta; manual runs
  follow `Since_Mode__c`.** Implemented as a per-run mode override through
  `HumanitixSyncLauncher` (`state.incremental` already exists; only plumbing is
  added).
- **Delta interval presets:** Off / 15m / 30m / 1h / 2h / 4h / 6h / 12h.
  Sub-hourly = multiple CronTriggers (15m → 4 jobs).
- **Daily run time:** HH:mm (scheduling user's timezone) or Off.
- **Mappings: full editor** — edit object mappings, create/edit field mappings.
  **Deactivate-only** (Apex cannot delete CMT records; deleted defaults are
  re-seeded on upgrade anyway).
- **Old component survives as a deprecated wrapper.** `humanitixSyncAdmin` was
  exposed to Home pages; subscriber orgs may have placed it. It becomes a thin
  wrapper around the new Dashboard child and is removed in a later major.

## Architecture

### LWC

```
humanitixSetup (exposed; lightning-tabset; lazy per-tab render)
 ├── humanitixSetupDashboard      today's card, ported (keeps first-run seeding hook)
 ├── humanitixSetupConnection     API key entry (write-only) + Test Connection
 ├── humanitixSetupSyncSettings   settings form + kill switch
 ├── humanitixSetupSchedule       interval + daily time, managed cron jobs
 └── humanitixSetupMappings       object list → field drill-in
      └── humanitixMappingFieldForm   modal create/edit for one field mapping
humanitixSetupUtils               shared JS: errorMessage, pollDeploy, constants
```

Only `humanitixSetup` (and the legacy wrapper) are exposed. The FlexiPage
`Humanitix_Setup_Home` flips to `humanitixSetup`.

### Apex

One controller per tab plus shared services, all `with sharing`:

| Class | Role |
|---|---|
| `HumanitixConnectionController` | key status/save, test connection |
| `HumanitixCredentialService` | isolates all ConnectApi credential calls |
| `HumanitixMetadataWriter` | shared CMT deploy + status ledger + polling read |
| `HumanitixSyncSettingsController` | settings DTO read/save; kill-switch DML |
| `HumanitixScheduleController` | schedule read/save, CronTrigger management |
| `HumanitixMappingAdminController` | mapping DTOs, describe, validate, save |

Every new class is added to the Admin permset `classAccesses` and to
`ADMIN_APEX_CLASSES` in `scripts/dev/generate-metadata.py` in the same commit.

### CMT writes and deploy feedback

Runtime CMT writes use `Metadata.Operations.enqueueDeployment` (the
`HumanitixMappingSeeder` pattern, including the `Test.isRunningTest()` guard).
Deploys are **per-field merge**, so every save sends the record's full field
set. Apex has no deploy-status API, so a new admin-only object
`Humanitix_Metadata_Deploy__c` (`Deploy_Job_Id__c` ext-id, `Status__c`
Pending/Succeeded/Failed, `Purpose__c`, `Error_Detail__c`, `Completed_At__c`)
is written by `HumanitixMetadataWriter.StatusCallback` and polled by the LWC
(2s interval, 120s advisory timeout).

### Connection (write-only key)

`ConnectApi.NamedCredentials`: `getCredential` (values return masked → "a key
is saved" display), `createCredential`/`patchCredential` with the `ApiKey`
credential value on principal `Humanitix_Named_Principal`. The key is never
logged, returned, or stored. Test Connection calls
`GET /v1/events?page=1` through `HumanitixHttpClient`. If ConnectApi is
unavailable or denied for a permset-only user, the tab falls back to showing
the manual Setup steps; the packaged permset does **not** gain Customize
Application.

### Schedule

Desired state lives on the DML-writable `Humanitix_Sync_Toggle__c` custom
setting: new `Delta_Interval_Minutes__c` Number(4,0) and
`Daily_Full_Sync_Time__c` Text(5, "HH:mm"); dead `Schedule_Cron__c` is removed.
Managed CronTrigger names: `Humanitix Delta Sync 1..4`, `Humanitix Daily Full
Sync`. Save = abort managed jobs by exact name, recreate from desired state,
write the setting. The tab surfaces drift (repair button), unmanaged
`Humanitix%` jobs, and a same-minute collision warning; help text notes the
overlap guard skips fires while a run is in flight.

`HumanitixSyncScheduler` gains a nullable `mode` member (no-arg constructor
keeps today's behaviour for jobs scheduled before upgrade);
`HumanitixSyncLauncher.start(triggerSource, runMode)` maps `Full` →
`incremental=false`, `Delta` → `true`, null → config.

### Mappings editor

Reads org CMT records, falling back to `HumanitixDefaultMappings` (flagged
`fromDefaults`) while the org has none. **First save materializes all defaults
plus the edits in one atomic container** (idempotent against a concurrently
running seeder thanks to merge semantics). Validation overlays pending edits
onto in-memory CMT sObjects and runs the existing
`HumanitixMappingConfig.fromRecords(...).validate()`; errors block the save.
Created field mappings get server-generated DeveloperNames `<Parent>_C<NN>`
(cannot collide with shipped `<Parent>_<NN>`). Target-field pickers come from a
cacheable describe endpoint guarded by `safeIdentifier`.

## Milestones

| # | Scope | Size |
|---|---|---|
| M1 | Tab shell, Dashboard promotion, deprecated wrapper, FlexiPage flip | S |
| M2 | Connection tab | M |
| M3 | Sync Settings tab + `HumanitixMetadataWriter` + deploy ledger | M/L |
| M4 | Schedule tab + per-run mode plumbing | M |
| M5 | Mappings editor (depends on M3) | L |

Each milestone leaves `main` releasable; suggested package checkpoints after
M1, M3, and M5. Version target v1.0.0-3.

## Constraints and conventions

- Metadata-API CMT record deploys are broken (Summer '26 gack);
  `**/customMetadata/**` stays force-ignored; Apex `Metadata.Operations` is the
  only write path.
- Apex tests must pass in both the dev org (CMT records exist) and the bare
  package-build org (none).
- New metadata defaults preserve current behaviour (schedule fields null = Off,
  ledger inert, no-arg scheduler path unchanged).
- User-facing UI copy and customer docs use no em dashes.
- Jest coverage stays at or above the CI gate; no workflow changes needed.
