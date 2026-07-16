# Field Mapping

The connector's behaviour is **entirely metadata-driven**. Two Custom Metadata
Types decide where every Humanitix field lands, so you can retarget any field to
your own object/field **without touching Apex**.

## The two Custom Metadata Types

### Humanitix Object Mapping

One record per *(Humanitix resource → target SObject)*.

| Field | Meaning |
| --- | --- |
| Source Resource | `Event` / `Order` / `Ticket` / `Tag` |
| Source Collection Path | For nested arrays — `ticketTypes`, `dates`, `additionalFields`. Blank = the record itself. |
| Target SObject | API name of the object to write, e.g. `Campaign`, `Contact`, or your own `My_Obj__c` |
| External Id Field | The upsert key field (used by `ExternalId` / `MatchNoUpdate`) |
| Match Strategy | `ExternalId`, `MatchByFields`, `MatchNoUpdate`, `AlwaysCreate` |
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
