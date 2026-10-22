# Event Selection and Contact Account: Design

**Date:** 2026-10-22
**Status:** Approved in brainstorming. Implements roadmap feature 3 (per-event
sync selection) with one deviation from the roadmap sketch, and adds a Contact
account choice (None, Event account, Person account). Target: package version
1.3.0 (milestone 3 may ship as 1.4.0, see Milestones).

## Context and goal

Humanitix asked for a UI to choose "All events" or "Selected events", mimicking
the Salesforce Settings screen of their official connector. That screen,
compared with the connector on 2026-10-22:

| Official setting | Connector today | This spec |
| --- | --- | --- |
| Sync Events: All / Selected Events, with an event picker | Future events only checkbox | Event Selection: All / Future only / Selected, with an in-app picker |
| Contact Settings (three radios) | Update Mode on the Order to Contact mapping (Mappings tab) | Unchanged |
| Create Account per event ("Humanitix - Event Name") | Not available. Order to Account is keyed on the buyer's organisation and ships inactive | Contact account choice: None (NPSP households), Event account, or Person account |
| Add Attendees to Campaign toggle | Order to Campaign Member mapping, active | Unchanged |
| Update Frequency: Daily / Hourly / On Request | Schedule tab | Unchanged |

### Decisions made in brainstorming

- **Scope:** event selection and a Contact account choice. A Contact Settings radio
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
- **Contact account is one three-way choice, not a toggle:** None, Event
  account, Person account. Household accounts are not built by the connector:
  in NPSP orgs with the Household Account model, NPSP already creates a
  Household Account when a Contact is inserted without one, so None covers
  them. Connector-built households for non-NPSP orgs are out of scope.
- **The Contact account choice saves with Save Settings** in the same metadata
  deploy as the sync setting record: one deploy, one poll. It is stored only
  as the active state of the mapping records it switches, so the Mappings tab
  and the Sync Settings tab can never disagree.
- **Person account is its own milestone**, so event selection and Event
  account are not held up by it.
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
  `selectedEventIds` (`List<String>`); `contactAccount` is added by feature 2.
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

## Feature 2: Contact account

One setting decides which Account a Humanitix buyer is linked to:

| Value | Label | What happens |
| --- | --- | --- |
| `None` | None (org default) | Today's behaviour. The connector leaves `Contact.AccountId` blank. In NPSP orgs, NPSP creates a Household Account for each new Contact. |
| `EventAccount` | Event account | One Account per synced event, named `Humanitix - Event Name`; buyers without an Account are linked to it. |
| `PersonAccount` | Person account | Buyers are created as Person Accounts instead of Contacts, matched by email. Needs Person Accounts enabled in the org. |

### Shared metadata

- `Account.Humanitix_Event_Id__c`: Text(255), external id, unique, label
  "Humanitix Event Id", help text "Used when Contact account is Event account
  on the Sync Settings tab: one Account per Humanitix event." Declared in
  `STANDARD_FIELDS["Account"]` so the permission set FLS is generated with it.
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
never removed or reordered. Every new record ships inactive, and
`HumanitixMappingConfig.validate()` already skips inactive mappings, so the
Person Account fields below never fail validation in an org without Person
Accounts.

**Object mapping `Event_to_Account`** ("Event to Account (optional)"): Source
Resource `Event`, Target `Account`, External Id Field `Humanitix_Event_Id__c`,
Match Strategy `ExternalId`, Update Mode `Always`, Load Order 14, Is Active
false. Description: "OPTIONAL: one Account per Humanitix event, named
Humanitix - Event Name. Turned on by Contact account = Event account on the
Sync Settings tab, together with Order_to_Contact_08."

| Field mapping | Source Path | Target Field | Data Type | Transform | Transform Arg |
| --- | --- | --- | --- | --- | --- |
| `Event_to_Account_01` | `_id` | `Humanitix_Event_Id__c` (external id) | Text | None | |
| `Event_to_Account_02` | `name` | `Name` | Text | Template | `Humanitix - {value}` |

**Field mapping `Order_to_Contact_08`** on `Order_to_Contact`: Source Path
`eventId`, Target Field `AccountId`, Data Type `Reference`, Transform Arg
`Account.Humanitix_Event_Id__c`, Overwrite With Blank false (an unresolved
Account never clears an existing AccountId), Is Active false.

Load Order 14 places the Account between the staging event (10) and the
Campaign (15). The Contact link in the Orders phase (18) relies on Accounts
being committed by the earlier Events phase, which they are.

**Object mapping `Order_to_PersonAccount`** ("Order to Person Account
(optional)"): Source Resource `Order`, Target `Account`, External Id Field
`Humanitix_Contact_Key__pc`, Match Strategy `MatchByFields`, Match Field Set
`PersonEmail`, Update Mode `BlanksOnly`, Load Order 18, Is Active false.
Description: "OPTIONAL: buyer becomes a Person Account, matched by email with
blanks-only updates. Turned on by Contact account = Person account on the Sync
Settings tab, which turns Order_to_Contact off. Needs Person Accounts enabled."

| Field mapping | Source Path | Target Field | Data Type | Transform | Default Value |
| --- | --- | --- | --- | --- | --- |
| `Order_to_PersonAccount_01` | `email` | `Humanitix_Contact_Key__pc` (external id) | Text | Lower | |
| `Order_to_PersonAccount_02` | `firstName` | `FirstName` | Text | None | |
| `Order_to_PersonAccount_03` | `lastName` | `LastName` | Text | None | `Unknown` |
| `Order_to_PersonAccount_04` | `email` | `PersonEmail` | Email | Lower | |
| `Order_to_PersonAccount_05` | `mobile` | `PersonMobilePhone` | Phone | None | |
| `Order_to_PersonAccount_06` | `organisation` | `Humanitix_Organisation__pc` | Text | None | |
| `Order_to_PersonAccount_07` | `_id` | `Humanitix_Last_Order_Id__pc` | Text | None | |
| `Order_to_PersonAccount_08` | *(none)* | `RecordTypeId` | Text | None | *(set on save, see below)* |

The `__pc` fields are the Person Account view of the packaged Contact fields;
Salesforce creates them automatically when Person Accounts are enabled, so the
package ships no new field for them.

The existing Campaign Member and staging Order mappings keep working unchanged:
both resolve the buyer through `Contact.Humanitix_Contact_Key__c`, and a Person
Account's person contact is a Contact record carrying that value.

### Mapping states per choice

Saving a Contact account value sets these `Is_Active__c` values. Only records
whose state actually changes are deployed.

| Record | None | Event account | Person account |
| --- | --- | --- | --- |
| `Order_to_Contact` | on | on | **off** |
| `Order_to_Contact_08` (AccountId) | off | **on** | off |
| `Event_to_Account` | off | **on** | off |
| `Order_to_PersonAccount` | off | off | **on** |

The effective value shown on the tab is derived from the same records:
Person account when `Order_to_PersonAccount` is active and `Order_to_Contact`
is not; Event account when `Event_to_Account` is active; None when none of
those three are active and `Order_to_Contact` is. Any other combination (made
on the Mappings tab or in Setup) shows as `Custom` with the notice "These
mappings were changed on the Mappings tab. Choose an option and save to apply
it." Saving any option then normalises the four records to the table above.

### Event account semantics (documented)

- One Account per synced event, respecting Event Selection.
- The Contact link follows the Order to Contact mapping's Update Mode. Under
  the shipped `BlanksOnly`, only Contacts with no Account are linked: new buyers
  join the event Account and existing records are untouched. Under `Always` the
  latest order's event wins. Under `Never` only newly created Contacts get it.
- NPSP orgs: a new Contact linked to an event Account does not get a Household
  Account.
- Leads have no Account; the Lead mapping is untouched.
- The Account name prefix is changed by editing the Template Transform Arg on
  the Mappings tab; there is no separate setting.

### Person account semantics (documented)

- Available only when Person Accounts are enabled, detected by
  `Schema.SObjectType.Account.fields.getMap().containsKey('ispersonaccount')`.
  In other orgs the option is shown disabled with an explanation.
- Record type: the save resolves the person record type to use. The tab lists
  the active Account record types where `IsPersonType = true` that the running
  user can use; with exactly one it is chosen silently, with several the admin
  picks one from a combobox shown under the radio group. The save writes its Id
  as the Default Value of `Order_to_PersonAccount_08` (a constant: no Source
  Path), alongside the activation. Choosing Person account with no person record
  type available is a validation error.
- Switching to Person account does not convert existing Contacts. A buyer who
  already exists as a business Contact gets a new Person Account, because the
  match runs on `PersonEmail`. The tab warns about this before saving.
- Switching away from Person account leaves existing Person Accounts in place;
  new buyers become Contacts again.

### Contact account control on the Sync Settings tab

A `lightning-radio-group` labelled **Contact account**, placed under Sync
Events, with field-level help "Which Account each Humanitix buyer is linked to
in Salesforce." Each option has a help line rendered under the group for the
selected value (copy is final; no em dashes):

- **None (org default):** "Buyers are created as Contacts with no Account set
  by the connector. In NPSP orgs, NPSP then creates a Household Account for each
  new Contact automatically. Choose this if you use NPSP households."
- **Event account:** "Creates one Account per synced event, named Humanitix -
  Event Name, and links buyers who do not have an Account yet to it. In NPSP
  orgs, these Contacts do not get a Household Account."
- **Person account:** "Creates each buyer as a Person Account instead of a
  Contact, matched by email. Existing Contacts are not converted, so a buyer
  who is already a Contact gets a new Person Account."
- Person account disabled note: "Person Accounts are not enabled in this org.
  Salesforce Support can enable them, and that change cannot be undone."
- Footer, always shown: "This switches the mappings listed on the Mappings
  tab. Changes there show here as Custom."

Data contract:

- `SettingsDto` gains `contactAccount` (`None` | `EventAccount` |
  `PersonAccount` | `Custom` on read), `personAccountsEnabled` (Boolean),
  `personRecordTypes` (list of `{ value: Id, label }`) and
  `personRecordTypeId` (the current Default Value of
  `Order_to_PersonAccount_08`, or the single available one).
- On save, `contactAccount = Custom` means "leave the mapping records alone".
  Any other value is compared with the effective state; when it differs, or
  Person account is chosen with a different record type, `saveSyncSettings`
  builds a `PendingChanges` holding the affected records, each copied from the
  effective record with `active` (and, for `_08`, the Default Value) changed,
  and appends `HumanitixMappingAdminController.deployRecordsFor(pending)` (a new
  public method that validates the candidate configuration and returns the
  records to deploy, including missing shipped defaults) to the sync setting
  record. The result is one `HumanitixMetadataWriter.deploy(records, 'Sync
  Settings')` call, polled by the tab exactly as today. A validation failure
  surfaces as an `AuraHandledException` before anything is deployed.

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
   A mapping save or a Contact account save therefore works even seconds after an
   upgrade, before the asynchronous seed has landed; the seeder's merge
   semantics make the two deploys idempotent.

## Docs

- **CONFIGURATION.md:** a Sync Events section replaces the Future events only
  bullet (modes, picker, edge semantics, and the In Future Only row in the
  settings table marked as superseded but honoured when Event Selection is
  blank); a new Contact account section with the three options, the mapping
  state table, and the Update Mode, NPSP and Person Account notes.
- **FIELD-MAPPING.md:** `Template` in the transforms list; the two new shipped
  inactive mappings in "What ships by default"; an upgrade note that the new
  records arrive inactive on the first Setup tab load after upgrading.
- **README.md:** feature list and comparison table rows for event selection
  and the Contact account choice.
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
  for a page, a last page and a 401; `contactAccount` is derived correctly
  for every row of the mapping state table and reads Custom otherwise; each
  transition deploys exactly the records whose state changes; an unchanged or
  Custom value deploys no mapping record; Person account without Person
  Accounts or without a person record type is rejected; the chosen record type
  lands as the Default Value of `Order_to_PersonAccount_08`.
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
  the DTO carries `eventSelection`, `selectedEventIds` and `contactAccount`;
  the Contact account help line follows the selected option; Person account is
  disabled with its note when `personAccountsEnabled` is false; the record type
  combobox appears only with several person record types; Custom shows its
  notice.
- `humanitixEventPicker`: page loop until the last page and at the cap;
  search; select and remove via table and pills; unknown-id pills; fetch
  failure with Refresh; `change` events.

**Scratch-org walkthrough** with the demo Humanitix account before building the
package version: pick events live, run a Selected sync and confirm unselected
events create nothing, switch Contact account to Event account and confirm the
Account and the Contact link, then repeat with Person account in a scratch org
with the `PersonAccounts` feature, then upgrade a scratch org from 1.2.0-1 and confirm the three new
records arrive inactive with no settings change.

## Milestones

| # | Scope | Ships in |
| --- | --- | --- |
| M1 | Event selection: config, engine filter, picker, Sync Settings radio | 1.3.0 |
| M2 | Seeder fix, Template transform, Event account, Contact account radio with None and Event account | 1.3.0 |
| M3 | Person account: mapping, detection, record type choice, Person account option | 1.3.0 if done before the build, otherwise 1.4.0 |

Each milestone leaves the branch releasable. Until M3 lands, the Person
account option is not rendered.

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
  (seeds `Event_to_Account`, `Order_to_PersonAccount`, their field mappings
  and `Order_to_Contact_08`, all inactive), verify by SOQL. Event Selection stays blank, so behaviour is
  identical until an admin chooses otherwise.
- **Demo org for Humanitix:** set Selected with a few events and turn the
  Contact account to Event account, so the walkthrough shows both features.

## Out of scope (recorded for later)

- Contact Settings radio and Add Attendees to Campaign toggle on the Sync
  Settings tab.
- Per-event `Sync_Enabled__c` checkbox on `Humanitix_Event__c` and catalog
  rows for unselected events (roadmap sketch, superseded).
- Connector-built Household Accounts for orgs without NPSP.
- Converting existing Contacts to Person Accounts.
- A UI setting for the Account name prefix.
- Linking Campaigns or Orders to the event Account.
- Lean mode (roadmap feature 2) and the revenue layer (feature 4).

## Success criteria

- An admin can choose All, Future only or Selected, pick events by name from a
  live Humanitix list, save, and the next run syncs only those events, with
  nothing created for the others.
- Contact account = Event account creates one `Humanitix - <Event Name>` Account per synced
  event and links new Contacts to it, without touching existing Contacts under
  the shipped BlanksOnly mode.
- Contact account = None keeps today's behaviour, so NPSP keeps creating
  Household Accounts.
- Contact account = Person account, in an org with Person Accounts, creates
  buyers as Person Accounts matched by email, and Campaign Members still link
  them to the event Campaign.
- Each option's help text explains its effect in the tab itself.
- Kaipatiki upgrades with identical behaviour and the new records arrive
  inactive.
- All Apex and Jest tests pass in both the seeded and the bare org; coverage
  stays at or above the CI gate.
