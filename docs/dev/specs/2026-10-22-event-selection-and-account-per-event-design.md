# Event Selection and Account per Event: Design

**Date:** 2026-10-22
**Status:** Approved in brainstorming. Implements roadmap feature 3 (per-event
sync selection) with one deviation from the roadmap sketch, and adds Account per
event. Target: package version 1.3.0.

## Context and goal

Humanitix asked for a UI to choose "All events" or "Selected events", mimicking
the Salesforce Settings screen of their official connector. That screen,
compared with the connector on 2026-10-22:

| Official setting | Connector today | This spec |
| --- | --- | --- |
| Sync Events: All / Selected Events, with an event picker | Future events only checkbox | Event Selection: All / Future only / Selected, with an in-app picker |
| Contact Settings (three radios) | Update Mode on the Order to Contact mapping (Mappings tab) | Unchanged |
| Create Account per event ("Humanitix - Event Name") | Not available. Order to Account is keyed on the buyer's organisation and ships inactive | Event to Account mapping, Contact AccountId mapping, and a toggle |
| Add Attendees to Campaign toggle | Order to Campaign Member mapping, active | Unchanged |
| Update Frequency: Daily / Hourly / On Request | Schedule tab | Unchanged |

### Decisions made in brainstorming

- **Scope:** event selection and Account per event. A Contact Settings radio
  and an Add Attendees toggle on the Sync Settings tab are deferred; both
  capabilities already exist as mapping settings.
- **Picker sourced live from the Humanitix API; selection stored as an id list
  on the Sync Setting record.** This deviates from the roadmap sketch (a
  `Sync_Enabled__c` checkbox on `Humanitix_Event__c` ticked from a list view).
  Consequence: unselected events create nothing in Salesforce, not even a
  staging row, and the picker works before any sync has run.
- **Selected mode keeps paging `/v1/events` with the `since` cursor and
  filters the page**, rather than fetching each selected event with
  `GET /v1/events/{id}`. The per-event GET has no `since` support, so every
  delta run would re-fetch every selected event, and it would add a second
  request shape to the queueable.
- **Three-way picklist** (All / FutureOnly / Selected) replaces the Future
  events only checkbox in the UI; the checkbox field stays and is honoured
  when the picklist is blank, so upgraded orgs change nothing.
- **The Account toggle saves with Save Settings** in the same metadata deploy
  as the sync setting record: one deploy, one poll.
- **Seeder fix:** upgraded orgs must receive newly shipped default mappings,
  which does not happen today.

## Feature 1: Event selection

### Configuration

Two new fields on `Humanitix_Sync_Setting__mdt`, declared in
`scripts/dev/generate-metadata.py` (SubscriberControlled, like the rest):

| Field | Type | Meaning |
| --- | --- | --- |
| `Event_Selection__c` | Picklist: `All`, `FutureOnly`, `Selected` | Which events the sync handles. Blank, or any value outside the three, resolves to the legacy behaviour: `In_Future_Only__c` true means `FutureOnly`, otherwise `All`. |
| `Selected_Event_Ids__c` | Long Text Area (131,072) | Comma-separated Humanitix event ids. Read only in `Selected` mode, but kept across mode changes so switching back to Selected restores the previous list. |

`HumanitixSyncConfig` gains:

- `eventSelection()`: the effective mode after the legacy resolution above.
- `selectedEventIds()`: `Set<String>` of trimmed, non-blank, de-duplicated ids
  (empty when blank).
- `inFutureOnly()` now returns `eventSelection() == 'FutureOnly'`, so the
  existing callers keep working.

The shipped `Humanitix_Sync_Setting.Default` record (generate-default-mappings.py,
then regenerate the static resource) sets `Event_Selection__c = All`. Upgraded
orgs keep their existing record, so their picklist stays blank and the legacy
checkbox rules.

### Run state and launcher

`HumanitixSyncState` gains `eventSelection` (String) and `selectedEventIds`
(`List<String>`), snapshotted at launch like every other setting. `inFutureOnly`
stays and is true only in FutureOnly mode.

`HumanitixSyncLauncher.start` adds one check after the enabled-resources check:
mode `Selected` with an empty id list throws
`LaunchException('Event Selection is Selected but no events are selected (Humanitix Sync Setting > Selected Event Ids).')`.

### Sync engine

**Events phase.** The request is unchanged: `inFutureOnly=true` is sent only in
FutureOnly mode (through `state.inFutureOnly`), never in Selected mode, and
`since` keeps working in every mode. In Selected mode the queueable drops every
parsed record whose `_id` is not in `selectedEventIds` before calling
`HumanitixMappingEngine.run`, so unselected events produce no records of any
kind. The page's log entry message records `N event(s) not selected, skipped`
(joined with any mapping errors); `recordsProcessed` counts mapped records only.
A page whose every record is filtered is still a successful page, and cursor
promotion is unchanged.

**Orders and Tickets phases.** `HumanitixSyncStateService.nextEventId` gains an
overload `nextEventId(String afterId, Set<String> onlyIds)`; a non-null set adds
`AND Humanitix_Id__c IN :onlyIds` to both keyset queries, and the existing
one-argument method delegates with null. The queueable passes
`selectedEventIds` in Selected mode and null otherwise.

**FutureOnly mode** is exactly today's checkbox behaviour: future events only
on the events request; Orders and Tickets still iterate every non-archived
staged event.

### Edge semantics (documented in CONFIGURATION.md)

- Unselecting an event stops its updates. Nothing is deleted; its Campaign,
  staging rows, Contacts and Campaign Members remain. Selecting it again
  resumes updates.
- An id in the list that Humanitix no longer returns is harmless: it never
  matches a page.
- Switching from Selected to All resumes every event. The id list is kept.

### Sync Settings tab

- The Future events only checkbox becomes a **Sync Events** radio group
  (`lightning-radio-group`) with three options: All events (`All`), Future
  events only (`FutureOnly`), Selected events (`Selected`). Each option carries
  one line of help text.
- Choosing Selected events reveals the event picker component below the radio
  group.
- `SettingsDto` replaces `inFutureOnly` with `eventSelection` (String) and
  `selectedEventIds` (`List<String>`); `accountPerEvent` is added by feature 2.
  `saveSyncSettings` writes `Event_Selection__c`, `Selected_Event_Ids__c`
  (comma-joined, null when the list is empty) and
  `In_Future_Only__c = (eventSelection == 'FutureOnly')` so the legacy field
  stays truthful for anyone reading it in Setup.
- Validation, server side and mirrored client side: `eventSelection` must be
  one of the three values; Selected requires at least one id; each id must
  match `^[A-Za-z0-9_-]{1,64}$`; ids are de-duplicated; at most 5,000 ids.
  Client side, Save Settings is disabled with the hint "Select at least one
  event" while Selected has an empty list.

### Event picker component (`humanitixEventPicker`)

A new LWC, owned by the settings tab but independent of saving.

**Public API:** `@api selectedIds` (array of strings), `@api disabled`
(Boolean). Dispatches `change` with `detail: { selectedIds }` on every
selection change.

**Data:** a new Apex method
`HumanitixSyncSettingsController.fetchHumanitixEvents(Integer page)` returning
`EventPageDto { List<EventSummary> events; Boolean hasNextPage; Integer page; }`
with `EventSummary { String id; String name; String startDate; String endDate; String timezone; Boolean isArchived; Boolean published; }`.
It does one callout through `HumanitixHttpClient(namedCredentialName)` to
`/v1/events?page=N&pageSize=100` and parses the body with
`HumanitixApiResponse.parse(body, 'events', status)`. A non-2xx status throws an
`AuraHandledException` such as
"Humanitix returned HTTP 401. Check the API key on the Connection tab." The
method is not cacheable: the list is live.

**Behaviour:**

- On first render, and on Refresh, the component loads pages sequentially until
  `hasNextPage` is false or 50 pages have loaded; at the cap it shows a notice
  that the list was cut at 5,000 events.
- It fetches every event, not future ones only, because past events can be a
  valid selection.
- Selected events appear as removable pills (`lightning-pill-container`) above
  the list. Removing a pill deselects. A saved id absent from the fetched list
  gets the pill label `Unknown event (<id>)` so it can be removed.
- A search input filters the table by name, case-insensitive substring. The
  component keeps its own selected set, so selection survives filtering; the
  table's `selected-rows` is derived from it.
- The table is a `lightning-datatable` with a checkbox column, `key-field="id"`,
  unlimited row selection, inside a scrollable container, sorted by start date
  descending so upcoming events are at the top. Columns: Event (name), Starts
  (date), Status: Archived when `isArchived`, otherwise Draft when `published`
  is false, otherwise Past when `endDate` is before now, otherwise Upcoming.
- While loading it shows a spinner. On a fetch failure it shows the error
  inline in an error-themed scoped notification, keeps showing the saved ids as
  pills, and offers a Refresh button.

## Feature 2: Account per event

### Metadata

- `Account.Humanitix_Event_Id__c`: Text(255), external id, unique, label
  "Humanitix Event Id", help text "Optional: enable Create an Account per event
  on the Sync Settings tab, or the Event to Account mapping, to create one
  Account per Humanitix event." Declared in `STANDARD_FIELDS["Account"]` so the
  permission set FLS is generated with it.
- The `Transform__c` picklist on `Humanitix_Field_Mapping__mdt` gains
  `Template`.

### Template transform

`HumanitixTypeCoercer` adds `Template`: a null raw value stays null (and falls
through to the mapping's defaults like every transform); otherwise the result
is Transform Arg with every `{value}` token replaced by the raw value as text.
`HumanitixMappingConfig.validate()` reports a Template mapping whose Transform
Arg is blank or lacks `{value}`, so a run fails fast the way other configuration
errors do; `HumanitixMappingAdminController.structuralProblems` reports the same
before a save. `Template` is added to the admin controller's transform
allow-list, the field form's transform options, and the transforms list in
FIELD-MAPPING.md. The existing `Concat` is unchanged (it joins with a colon,
which cannot produce the official connector's naming).

### Shipped mappings

Appended to `scripts/dev/generate-default-mappings.py`; shipped entries are
never removed or reordered. All three records ship inactive.

**Object mapping `Event_to_Account`** ("Event to Account (optional)"): Source
Resource `Event`, Target `Account`, External Id Field `Humanitix_Event_Id__c`,
Match Strategy `ExternalId`, Update Mode `Always`, Load Order 14, Is Active
false. Description: "OPTIONAL: one Account per Humanitix event, named
Humanitix - Event Name. Turn on with Create an Account per event on the Sync
Settings tab, which also activates the Contact AccountId field mapping
Order_to_Contact_08."

| Field mapping | Source Path | Target Field | Data Type | Transform | Transform Arg |
| --- | --- | --- | --- | --- | --- |
| `Event_to_Account_01` | `_id` | `Humanitix_Event_Id__c` (external id) | Text | None | |
| `Event_to_Account_02` | `name` | `Name` | Text | Template | `Humanitix - {value}` |

**Field mapping `Order_to_Contact_08`** on `Order_to_Contact`: Source Path
`eventId`, Target Field `AccountId`, Data Type `Reference`, Transform Arg
`Account.Humanitix_Event_Id__c`, Overwrite With Blank false (an unresolved
Account never clears an existing AccountId), Is Active false.

Load Order 14 places the Account between the staging event (10) and the
Campaign (15); nothing depends on the order within the Events phase, but the
Contact link in the Orders phase (18) relies on Accounts being committed by an
earlier phase, which they are.

### Semantics (documented in CONFIGURATION.md and FIELD-MAPPING.md)

- One Account per synced event, respecting Event Selection.
- The Contact link follows the Order to Contact mapping's Update Mode. Under
  the shipped `BlanksOnly`, only Contacts with no Account are linked: new buyers
  join the event Account and existing records are untouched. Under `Always` the
  latest order's event wins. Under `Never` only newly created Contacts get it.
- NPSP orgs: a Contact inserted with an Account already set does not get a
  Household Account.
- Leads have no Account; the Lead mapping is untouched.
- The Account name prefix is changed by editing the Template Transform Arg on
  the Mappings tab; there is no separate setting.

### Toggle on the Sync Settings tab

- `lightning-input type="toggle"` labelled "Create an Account per event", help
  text: "Creates one Account per synced event, named Humanitix - Event Name,
  and links new Contacts to it. This switches the Event to Account mapping and
  the Contact AccountId field mapping (Order_to_Contact_08) on or off. The
  Mappings tab shows the same records."
- `SettingsDto.accountPerEvent` reflects the effective `Is_Active__c` of
  `Event_to_Account`: the org record when the org has mapping records, else the
  shipped default. An org that has mapping records but no `Event_to_Account`
  record yet (upgraded, seed not landed) reads as false.
- On save, `saveSyncSettings` compares `dto.accountPerEvent` with that effective
  state. When they differ it builds a `PendingChanges` holding the
  `Event_to_Account` object mapping and the `Order_to_Contact_08` field mapping,
  each with `active` set to the toggle's value and every other field copied from
  the effective record, and appends
  `HumanitixMappingAdminController.deployRecordsFor(pending)` (a new public
  method that validates the candidate configuration and returns the records to
  deploy, including missing shipped defaults) to the sync setting record. The
  result is one `HumanitixMetadataWriter.deploy(records, 'Sync Settings')` call,
  polled by the tab exactly as today. A validation failure surfaces as an
  `AuraHandledException` before anything is deployed.
- If an admin has customised the pair (for example the object mapping active
  and the field mapping inactive), the toggle shows the object mapping's state;
  saving with the toggle unchanged touches neither record, saving it Off
  deactivates both, saving it On activates both.

### Seeding newly shipped defaults on upgrade

Today `HumanitixSyncAdminController.ensureDefaultMappings()` returns early when
the org has any mapping record, so an upgraded org never receives defaults
added in a later version, and the documented promise that a deleted default
returns on upgrade is not currently true. Two changes:

1. `ensureDefaultMappings()` enqueues `HumanitixMappingSeeder` (unless one is
   already in flight) whenever `HumanitixMappingSeeder.missingDefaults()` is
   non-empty, and returns true in that case. The seeder already deploys missing
   records only, so edited mappings are never touched.
2. `HumanitixMappingAdminController`'s effective-records helpers overlay the
   missing shipped defaults (flagged `fromDefaults`) onto the org's records in
   every org, not only unseeded ones, so the Mappings tab lists them,
   validation knows the new parents, and `deployRecords` always includes them.
   A mapping save or a toggle save therefore works even seconds after an
   upgrade, before the asynchronous seed has landed; the seeder's merge
   semantics make the two deploys idempotent.

## Docs

- **CONFIGURATION.md:** a Sync Events section replaces the Future events only
  bullet (modes, picker, edge semantics, and the In Future Only row in the
  settings table marked as superseded but honoured when Event Selection is
  blank); a new Account per event section with the Update Mode and NPSP notes.
- **FIELD-MAPPING.md:** `Template` in the transforms list; the two new shipped
  inactive mappings in "What ships by default"; an upgrade note that the new
  records arrive inactive on the first Setup tab load after upgrading.
- **README.md:** feature list and comparison table rows for event selection
  and Account per event.
- **ARCHITECTURE.md:** one line on the Selected filter in the Events phase and
  the filtered keyset in Orders and Tickets.
- **Roadmap spec** (`2026-07-30-connector-improvement-roadmap-design.md`):
  mark feature 3 shipped and record the deviation (API-sourced picker and id
  list instead of a per-event checkbox).
- No em dashes in any user-facing copy or customer doc.

## Testing

**Apex** (must pass in the seeded dev org and in the bare package-build org):

- `HumanitixSyncConfigTest`: new accessors; blank picklist resolves from the
  legacy checkbox; unknown value resolves the same way; id parsing trims,
  skips blanks and de-duplicates.
- `HumanitixSyncLauncherTest`: snapshot of the new state fields; Selected with
  an empty list throws.
- `HumanitixSyncQueueableTest`: Selected mode drops unselected events before
  mapping with the skipped count in the log entry; an all-filtered page still
  promotes the cursor; `inFutureOnly` is never sent in Selected mode; Orders
  and Tickets iterate only selected events; `nextEventId` overload.
- `HumanitixSyncSettingsControllerTest`: DTO round trip for the new fields;
  every validation rule; `fetchHumanitixEvents` against `HumanitixCalloutMock`
  for a page, a last page and a 401; `accountPerEvent` reflects the effective
  state; a toggle change appends both mapping records to the deploy and an
  unchanged toggle appends nothing.
- `HumanitixTypeCoercerTest` and `HumanitixMappingConfigTest`: Template
  substitution, null pass-through, and validation of a missing `{value}`.
- `HumanitixDefaultMappingsTest`: the three new records exist, inactive, with
  the expected values.
- `HumanitixMappingAdminControllerTest` and `HumanitixSyncAdminControllerTest`:
  missing defaults are overlaid and deployed in a seeded org; the Setup tab
  triggers the seeder when any default is missing.

**Jest:**

- `humanitixSetupSyncSettings`: the radio group replaces the checkbox; the
  picker appears only for Selected; Save is disabled for an empty selection;
  the DTO carries `eventSelection`, `selectedEventIds` and `accountPerEvent`.
- `humanitixEventPicker`: page loop until the last page and at the cap;
  search; select and remove via table and pills; unknown-id pills; fetch
  failure with Refresh; `change` events.

**Scratch-org walkthrough** with the demo Humanitix account before building the
package version: pick events live, run a Selected sync and confirm unselected
events create nothing, flip the Account toggle and confirm the Account and the
Contact link, then upgrade a scratch org from 1.2.0-1 and confirm the three new
records arrive inactive with no settings change.

## Packaging and migration

- `sfdx-project.json` moves to `1.3.0.NEXT` (versionName "Version 1.3"); build
  and promote per PUBLISHING.md; GitHub release `v1.3.0-1`; swap the install
  ids in README.md, INSTALL.md and PUBLISHING.md.
- The default records keep shipping through the static resource and the seeder;
  after editing the generators, regenerate the resource before building.
- New classes or components: `humanitixEventPicker` (LWC only). Any new Apex
  class would be added to the admin permission set and to `ADMIN_APEX_CLASSES`
  in the metadata generator in the same commit; this design adds none.
- **Kaipatiki:** install the new version, open the Humanitix Setup tab once
  (seeds `Event_to_Account`, its two field mappings and `Order_to_Contact_08`,
  all inactive), verify by SOQL. Event Selection stays blank, so behaviour is
  identical until an admin chooses otherwise.
- **Demo org for Humanitix:** set Selected with a few events and turn the
  Account toggle on, so the walkthrough shows both features.

## Out of scope (recorded for later)

- Contact Settings radio and Add Attendees to Campaign toggle on the Sync
  Settings tab.
- Per-event `Sync_Enabled__c` checkbox on `Humanitix_Event__c` and catalog
  rows for unselected events (roadmap sketch, superseded).
- A UI setting for the Account name prefix.
- Linking Campaigns or Orders to the event Account.
- Lean mode (roadmap feature 2) and the revenue layer (feature 4).

## Success criteria

- An admin can choose All, Future only or Selected, pick events by name from a
  live Humanitix list, save, and the next run syncs only those events, with
  nothing created for the others.
- The Account toggle creates one `Humanitix - <Event Name>` Account per synced
  event and links new Contacts to it, without touching existing Contacts under
  the shipped BlanksOnly mode.
- Kaipatiki upgrades with identical behaviour and the new records arrive
  inactive.
- All Apex and Jest tests pass in both the seeded and the bare org; coverage
  stays at or above the CI gate.
