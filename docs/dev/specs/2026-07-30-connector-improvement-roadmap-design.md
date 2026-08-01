# Connector Improvement Roadmap — Design

**Date:** 2026-07-30
**Status:** Approved in brainstorming; feature ① specced at full depth, ②–④ at roadmap depth (each gets its own detailed plan before implementation).

## Context and goal

This project is the open-source alternative to the official Humanitix Salesforce
connector (managed package by AlphaSys, documented at
help.humanitix.com/en/articles/8905580). Verified against that article on
2026-07-30: the official connector also creates a custom-object layer (Orders,
Tickets, Order Attributes, Ticket Attributes, Ticket Types, Dates) alongside
Campaigns and Contacts, syncs one-way, offers daily/hourly/on-request frequency,
all-or-selected event scoping, three contact-matching modes, and no Lead
support. Field customisation there relies on Process Builder.

**Goal: make this the best Humanitix connector** — match the official
connector's configurability where it leads (event selection, matching modes)
and extend past it where it cannot go (lean mode, revenue layer, open source,
CMT-driven remapping, incremental sync, observability).

### Decisions already made

- **Evolve the existing codebase; no rewrite.** A from-scratch generic design
  converges on the current architecture (External Credential auth, Queueable
  chain with `since` cursors, CMT mapping engine, staging + standard layers,
  unlocked package).
- **The staging layer stays.** Removing it was designed and rejected: the
  official connector keeps the same layer because ticketing data (per-ticket
  records, no-email attendees, checkout answers, sessions) does not fit
  Campaign/Contact/CampaignMember grain. Removal would put this connector
  *below* official parity. Orgs that want minimal footprint get **lean mode**
  (feature ②) instead.

## Build order

| # | Feature | Size | Why this position |
|---|---------|------|-------------------|
| ① | Contact matching modes | S | Finishes the `Update_Blanks_Only__c` work already in the tree; unblocks the open Kaipatiki duplicate-rule decision. |
| ② | Lean mode | S | Independent, mostly config + guard + docs; establishes mapping toggles as a supported surface. |
| ③ | Per-event sync selection | M | Builds on ②'s toggle contract; closes the biggest genericity gap vs official. |
| ④ | Revenue layer (standard Order) | L | Largest; benefits from settled matching semantics. Ships inactive, opt-in. |

Each feature ships as its own spec → plan → implementation → package version.

---

## ① Contact matching modes (full depth)

### Problem

Different orgs want different behaviour when a Humanitix buyer matches an
existing Contact: some treat Salesforce as source of truth (never overwrite),
some want Humanitix to win (always update), some want gap-filling only, and
some rely on their own duplicate rules and want plain inserts. Today the
connector has one hard-wired behaviour per mapping (`Match_Strategy__c` plus
the uncommitted `Update_Blanks_Only__c` checkbox). The official connector
offers three modes; we should offer four, per mapping.

### Design

Replace the work-in-progress `Update_Blanks_Only__c` checkbox on
`Humanitix_Object_Mapping__mdt` with a picklist:

- **`Update_Mode__c`** (picklist): `Always` | `BlanksOnly` | `Never`.
  Blank defaults to `Always` (today's behaviour for every mapping except the
  in-flight Order→Contact change).

Behaviour matrix (per object mapping):

| Match_Strategy__c | Update_Mode = Always | BlanksOnly | Never |
|---|---|---|---|
| `ExternalId` | Upsert (create + full update) — current behaviour | Create new; on existing, set only fields that are currently blank | Create new; existing rows produce no DML |
| `MatchByFields` | Match then full update; create if unmatched | Match then fill blanks only; create if unmatched | Match then skip; create if unmatched |
| `AlwaysCreate` | *(Update_Mode ignored — documented; always inserts)* | ignored | ignored |

Implementation notes:

- `HumanitixMappingConfig` swaps `updateBlanksOnly : Boolean` for
  `updateMode : String` (normalised, validated; unknown value → config error
  logged, mapping skipped — consistent with existing config validation like the
  MatchByFields/no-field-set check).
- `HumanitixPersister` already queries existing targets for `MatchByFields` and
  for the blanks-only path; `Never` reuses that query and drops matched rows
  from the DML list. For `ExternalId` + (`BlanksOnly`|`Never`) the persister
  must pre-query by external id instead of blind upsert (same pattern, keyed on
  the external id field).
- In-page duplicate keys keep their existing collapse behaviour; mode applies
  after collapse.
- Field-level `Overwrite_Blank__c` on `Humanitix_Field_Mapping__mdt` keeps its
  meaning (whether a blank source value may blank a target field) and composes
  with the object-level mode; document the combination table in
  FIELD-MAPPING.md.

### Duplicate-rule interplay (documented, not coded)

- `AlwaysCreate` in an org with active duplicate rules set to Block → inserts
  fail per record and surface as `Partial`/`Failed` log entries (existing fault
  isolation). Docs recommend Report-not-Block rules, or `MatchByFields`.
- `MatchByFields(Email)` updates at most one existing Contact; which one is
  chosen when an org already holds duplicates is a documented limitation (the
  planning phase verifies and documents the current selection behaviour).

### Shipped defaults

- `Order_to_Contact`: `MatchByFields(Email)` + `Update_Mode = BlanksOnly`
  (preserves the behaviour the WIP checkbox introduced).
- All other mappings: `Update_Mode` blank → `Always` (no behaviour change).

### Migration

`Update_Blanks_Only__c` has never shipped in a released package version, so it
is removed outright from source (field, config loader, persister branches,
CMT record values, tests). One runbook check: the Kaipatiki org was
source-deployed — verify whether the checkbox field reached that org and delete
it there after the replacement deploys. Kaipatiki's open duplicate-rule
decision becomes choosing `Update_Mode__c` on one CMT record.

### Testing

- Persister unit tests: 3 strategies × 3 modes matrix, bulk (200+ records),
  in-page duplicate collapse under each mode, external-id pre-query path.
- Config tests: picklist validation, blank default, AlwaysCreate+mode ignored.
- Regression: existing mapping-engine and queueable tests unchanged.

---

## ② Lean mode (roadmap depth)

Standard-objects-only operation as a documented, tested configuration — not a
package variant. An org deactivates the staging child mappings
(`Order_to_Order`, `Ticket_to_Ticket`, attributes, ticket types, event dates,
tags) via the existing `Is_Active__c` toggles and disables unneeded phases via
`Enabled_Resources__c`. The skinny `Humanitix_Event__c` rows stay — they are
the Orders/Tickets work-list (`HumanitixSyncStateService.nextEventId()`).

Code change (one): a guard so a phase whose resource has zero active object
mappings makes **no callouts** — logs a `Skipped` entry and advances. Today a
fully-deactivated resource would still burn API calls to map nothing.

Deliverables: the guard + tests; a CONFIGURATION.md "lean mode" section with an
explicit what-you-give-up table (per-ticket records, no-email attendees,
checkout answers, sessions, tags); guidance for hiding staging tabs via
permission set; scratch-org test matrix (full vs lean) in CI.

---

## ③ Per-event sync selection (roadmap depth)

New `Event_Selection__c` picklist on `Humanitix_Sync_Setting__mdt`:
`All` | `FutureOnly` | `Selected`. Blank falls back to the legacy
`In_Future_Only__c` checkbox (kept, honoured, documented as superseded).

`Selected` mode: new `Sync_Enabled__c` checkbox (default unchecked) on
`Humanitix_Event__c`. The Events phase still catalogs **all** events (cheap
rows are what make selection possible); Campaign mapping and the Orders/Tickets
phases process only flagged events — `nextEventId()` adds the filter, and the
Event→Campaign mapping skips unflagged records. Admins tick events on the
existing tab's list view; no custom UI in v1.

Edge semantics (documented): unselecting an already-synced event stops updates
but deletes nothing; switching an org to `Selected` with nothing flagged syncs
no child data until events are ticked.

---

## ④ Revenue layer — standard Order (roadmap depth)

Additive mapping `Order_to_StdOrder`, shipped **inactive** (opt-in, like
Lead/Account today). No staging change; ticket detail stays in staging.

- New fields on standard Order: `Humanitix_Order_Id__c` (external id, upsert
  key), financial set from `totals` (total, net, refunds, donation — final list
  at planning), `Humanitix_Financial_Status__c`, `Humanitix_Sales_Channel__c`,
  `Humanitix_Campaign__c` (lookup, resolved by `Humanitix_Event_Id__c`),
  `Humanitix_Last_Sync__c`.
- Required standard fields: `EffectiveDate` ← order completed date
  (timezone-correct via existing `IsoToDateInTz`), `Status` ← constant `Draft`
  (never Activated, so upserts don't fight activation locks),
  `BillToContactId` ← buyer Contact, `AccountId` ← buyer Contact's Account
  (two-hop resolver extension, NPSP-household-friendly) with a configurable
  bucket-Account fallback (new sync-setting field). An order resolves to no
  Account only when the buyer Contact has none *and* no bucket Account is
  configured — such orders are skipped with a logged entry.
- Orders without an email still create an Order (bucket Account, no bill-to
  contact) so campaign revenue stays complete.
- Follow-ons recorded, not built: ticket-summary rollup fields on Order
  (simple staging rollup), NPSP Opportunity variant as an alternative mapping.
- No OrderItem/Product2/Pricebook machinery.

---

## Out of scope (recorded for later)

Multi-account/multi-region credentials; periodic full-reconciliation sweep for
hard deletes; NPSP Opportunity mapping (follow-on to ④); ticket-summary rollup
on Order (follow-on to ④); AppExchange listing; custom selection UI for ③.

## Packaging and migration notes

- Every feature lands behind existing patterns: new CMT fields default to
  current behaviour; new mappings ship inactive. No breaking changes; versions
  are minor (v1.x).
- While the Summer '26 platform bug blocks CustomMetadata record deploys, CMT
  records are seeded via Apex `Metadata.Operations`; package versions build
  once the platform fix lands.
- README comparison table is updated as each feature ships — including the new
  rows for matching modes, event selection, and revenue layer.

## Success criteria

- Feature parity or better vs the official connector on: event selection,
  matching modes, sync frequency, standard-object coverage — while keeping the
  existing leads: open source, no-code remapping, incremental sync, lean mode,
  Lead support, observability.
- Kaipatiki upgrades through each version with no behaviour change until they
  opt in (their FullPull config keeps working; ① requires only picking an
  `Update_Mode__c` value).
- All new behaviour covered by unit tests at bulk scale; scratch-org CI matrix
  covers full and lean configurations.
