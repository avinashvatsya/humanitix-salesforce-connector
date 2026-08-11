# Field Mapping

The connector's behaviour is **entirely metadata-driven**. Two Custom Metadata
Types decide where every Humanitix field lands, so you can retarget any field to
your own object/field **without touching Apex**.

## Editing mappings in the app

The **Mappings** tab of *Humanitix Setup* is the quickest way to work with these
records. It lists every object mapping, and opening one shows the field mappings
underneath it. From there you can:

- **Edit an object mapping.** Match Strategy, Update Mode, Match Field Set, Load
  Order and Is Active.
- **Edit or create a field mapping.** The target field comes from a picker of the
  writable fields on that mapping's target object, so an API name can't be
  mistyped.
- **Validate before saving.** Your pending changes are checked the same way the
  sync engine checks the configuration at the start of a run, and the save is
  blocked while anything is wrong.

Saving starts a Custom Metadata deployment, which Salesforce runs asynchronously,
so a save takes a few seconds rather than being instant. The page reports the
outcome once the deployment finishes.

Two things work differently from ordinary records:

**Mappings are deactivated, never deleted.** Apex cannot delete Custom Metadata
records, and a deleted shipped record would be re-created by the next package
upgrade in any case. To retire a mapping, clear its **Is Active** checkbox.

**The first save materialises the shipped defaults.** Until an org saves a mapping
of its own, the tab shows the defaults that ship with the package. The first save
copies *all* of those defaults into your org as Custom Metadata records with your
edits applied, and from then on your org's records are what the sync engine
reads.

Field mappings you create are named for you, as `<Object mapping>_C<NN>`, for
example `Event_to_Event_C01`. The `C` marks the record as yours, so a package
upgrade can never collide with it.

The same records stay editable in **Setup → Custom Metadata Types**, and the
reference below applies to both routes.

## The two Custom Metadata Types

### Humanitix Object Mapping

One record per *(Humanitix resource → target SObject)*.

| Field | Meaning |
| --- | --- |
| Source Resource | `Event` / `Order` / `Ticket` / `Tag` |
| Source Collection Path | For nested arrays — `ticketTypes`, `dates`, `additionalFields`. Blank = the record itself. |
| Target SObject | API name of the object to write, e.g. `Campaign`, `Contact`, or your own `My_Obj__c` |
| External Id Field | The upsert key field (used by `ExternalId`) |
| Match Strategy | `ExternalId`, `MatchByFields`, `AlwaysCreate` |
| Update Mode | `Always` (default), `BlanksOnly`, `Never` — how matched/existing records are updated |
| Match Field Set | Comma-separated target fields for `MatchByFields`, e.g. `CampaignId,ContactId` |
| Load Order | Lower runs first, so parents commit before children resolve |
| Is Active | Turn a mapping on/off |

### Humanitix Field Mapping

One record per *(source path → target field)*, linked to its Object Mapping by
`Object Mapping` (the parent's Developer Name).

| Field | Meaning |
| --- | --- |
| Source Path | Dotted JSON path, e.g. `totals.grossSales`, `checkIn.checkedIn`. `$parent.`/`$root.` reach the enclosing record in a collection. |
| Target Field | Field API name on the target object |
| Data Type | `Text`, `LongText`, `DateTime`, `Date`, `Decimal`, `Currency`, `Integer`, `Boolean`, `Email`, `Phone`, `Url`, `Reference` |
| Transform | see below |
| Transform Arg | Argument for the transform (or, for `Reference`, the target `Object.ExternalIdField`) |
| Is External Id | Marks the field mapping that populates the external id |
| Overwrite With Blank | If false, a null source value won't overwrite an existing value |

### Transforms

`None`, `Trim`, `Upper`, `Lower`, `IsoToDateTime`, `IsoToDateInTz` (arg = a path to
the timezone; avoids UTC off-by-one on dates), `DecimalMoney` (pass-through — money
is already in major units), `BoolMap`, `StaticValue` (arg = the literal),
`Concat` (arg = a prefix path/literal; joins with `:`), `JoinArray` (arg =
separator, default `,`), `ToJson`.

### References (lookups)

A field mapping with **Data Type = `Reference`** resolves a lookup by external id:
the source value (after its Transform, e.g. `Lower` to normalise an email) is
matched against **Transform Arg = `<Object>.<ExternalIdField>`**. If no parent is
found the lookup is left null — children are never orphaned or mislinked. Because
resolution reads committed data, keep parents at a lower Load Order than children.

## Update modes

`Update Mode` controls what happens when an incoming Humanitix record matches a
record that already exists in Salesforce:

| Match Strategy | `Always` (default) | `BlanksOnly` | `Never` |
| --- | --- | --- | --- |
| `ExternalId` | Upsert: existing records are updated with the latest Humanitix values | Only fields that are currently blank are filled; existing values are never overwritten | Existing records are left untouched; only new keys are inserted |
| `MatchByFields` | Matched records are fully updated | Matched records get blank fields filled only | Matched records are left untouched |
| `AlwaysCreate` | *(ignored — every row is inserted)* | *(ignored)* | *(ignored)* |

Unmatched/new records are always inserted in full, whatever the mode.

**Interaction with field-level `Overwrite With Blank`:** `Overwrite With Blank` on a Field
Mapping decides whether a *blank source value* may clear a populated target
field, and only applies when the mode allows the field to be written at all
(`Always`). Under `BlanksOnly`, populated target fields are never written,
so `Overwrite With Blank` has no effect; under `Never`, nothing on a matched record
is written.

**Interaction with duplicate rules:** `AlwaysCreate` in an org whose duplicate
rules are set to *Block* will have those inserts rejected — they surface as
failed rows in the sync log (the run itself continues). Prefer `MatchByFields`
on Email, or set the duplicate rule to *Report*. `MatchByFields` updates at
most one existing record per key; which one is chosen when the org already
holds duplicates is not defined — merge duplicates first for deterministic
results.

## What ships by default

| Resource | Targets (active) |
| --- | --- |
| Event | `Humanitix_Event__c` (+ nested `Humanitix_Ticket_Type__c`, `Humanitix_Event_Date__c`) **and** **Campaign** |
| Order | `Humanitix_Order__c` (+ `Humanitix_Order_Attribute__c`), **Contact** (buyer, matched by lower-cased email), **Campaign Member** (buyer ↔ event campaign, one per Contact+Campaign) |
| Ticket | `Humanitix_Ticket__c` (+ `Humanitix_Ticket_Attribute__c`) — attendee detail, linked to its Event and Order |
| Tag | `Humanitix_Tag__c` |

Shipped **inactive** (flip `Is Active` to enable): **Order → Lead** and
**Order → Account**.

The faithful `Humanitix_*__c` staging objects are the system of record; the
standard-object mappings are the CRM-facing layer you can retarget.

## Recipes

**Repoint a field.** To store the event's `slug` on a Campaign field of yours,
edit the `Event_to_Campaign` mapping's field records (or add one): Source Path
`slug`, Target Field `My_Slug__c`, Data Type `Text`.

**Send attendees to Leads instead of Contacts.** Activate the `Order_to_Lead`
mapping and deactivate `Order_to_Contact` (and, if you use it,
`Order_to_CampaignMember`, which resolves a Contact).

**Map to a completely custom object.** Create a new Object Mapping: Source Resource
`Ticket`, Target SObject `My_Attendee__c`, External Id Field `My_Ext_Id__c`, then
Field Mappings for each field. Add a `Reference` field mapping to link back to your
event object.

**Upgrade safety.** The default mapping records ship with *Subscriber Controlled*
fields, so your edits to them survive package upgrades. Prefer editing existing
records or adding your own over deleting shipped ones.

> Tip: after any mapping change, the engine validates every active mapping against
> your org schema on the next run and fails fast with a clear message if a target
> object/field doesn't exist.
