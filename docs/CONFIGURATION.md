# Configuration

## 1. Enter your Humanitix API key (required)

The key is stored encrypted in an **External Credential** — never in code or
metadata. You enter it once, in Setup:

1. **Setup → Security → Named Credentials → External Credentials** tab → open
   **Humanitix API**.
2. Under **Principals**, open **Humanitix_Named_Principal**.
3. Under **Authentication Parameters**, add (or confirm) a parameter named exactly
   **`ApiKey`** and paste your Humanitix API key as its value. **Save.**
4. Back on the **Named Credentials** tab, open **Humanitix API** and confirm:
   - URL = `https://api.humanitix.com`
   - *Generate Authorization Header* = **unchecked**
   - *Allow Formulas in HTTP Header* = **checked**
   - Custom header `x-api-key` = `{!$Credential.HumanitixAPI.ApiKey}`

Verify with **Setup → Developer Console → Debug → Open Execute Anonymous**:

```apex
System.debug(new HumanitixHttpClient().get('/v1/events?page=1').getStatusCode()); // expect 200
```

- `401` / `403` → the key is wrong, or the permission set (callout principal) isn't assigned.
- `200` → you're connected.

## 2. Make the running user a Marketing User (required for Campaigns)

Creating Campaigns and Campaign Members requires the syncing user to be a
**Marketing User** (or have *Modify All Data*). Setup → Users → edit the user →
check **Marketing User**. If you sync from the automated/scheduled context, make
sure that user qualifies.

## 3. Sync settings

Edit **Setup → Custom Metadata Types → Humanitix Sync Setting → Manage Records →
Default**:

| Field | Default | Purpose |
| --- | --- | --- |
| Page Size | 100 | Records per API page |
| Enabled Resources | `Events,Orders,Tickets,Tags` | Which resources to sync (comma-separated) |
| In Future Only | false | Only sync events ending in the future |
| Ticket Status Filter | *(blank)* | e.g. `complete` to skip cancelled tickets |
| Max Retries | 5 | Retries on 429/5xx before a page is marked failed |
| Retry Delay Minutes | 5 | Base backoff (whole minutes) |
| Since Mode | `Modified` | `Modified` = incremental via `since`; `FullPull` = always full |
| Named Credential Name | `HumanitixAPI` | Which Named Credential to call |
| Consecutive Failure Threshold | 5 | Circuit-breaker signal on a cursor |

### The `since` question

The connector's incremental mode assumes the API's `since` parameter filters on
**last-modified** time. The public spec doesn't state this. Confirm it once with
the included spike (your key stays on your machine):

```bash
HUMANITIX_API_KEY=your-key node scripts/spike.mjs
```

If the spike reports that `since` filters on *created* time (or is unclear), set
**Since Mode = `FullPull`** so every run re-pulls fully and you never miss edits.

## 4. Kill switch

**Setup → Custom Settings → Humanitix Sync Toggle → Manage → New** (org default) →
uncheck **Sync Enabled** to immediately stop new and in-flight runs. Defaults to
enabled when no record exists.

## 5. Running the sync

- **On demand:** *Humanitix Integration* app → *Humanitix Setup* tab → **Run Sync Now**.
- **Scheduled:** Execute Anonymous (or a Setup → Scheduled Jobs entry):
  ```apex
  HumanitixSyncScheduler.schedule('Humanitix Nightly Sync', '0 0 2 * * ?'); // daily 02:00
  ```
- **From a Flow / Agentforce:** add the **Run Humanitix Sync** invocable action.

Monitor runs on the **Humanitix Sync Logs** tab — each run has a header (status,
totals) and per-resource/per-event entries with any error messages.

## 6. Changing what maps where

All object/field bindings live in Custom Metadata and are fully remappable with no
code. See **[FIELD-MAPPING.md](FIELD-MAPPING.md)**.

## Known limitations

- **Attendee email:** Humanitix tickets carry no email (only the order does), so
  attendees are de-duplicated to the **buyer's** Contact by email. Per-ticket
  attendee detail is always preserved on `Humanitix_Ticket__c`.
- **Hard deletes aren't reconciled:** a read-only `since` pull can't observe a
  deletion. Cancellations/refunds/archival are captured as *status* fields
  (`Status__c`, `Financial_Status__c`, `Is_Archived__c`, `Cancelled_At__c`), not by
  removing records. A periodic full-reconciliation sweep is on the roadmap.
- **Marketing User** is required for the Campaign/Campaign Member mappings (above).
- **Money** values are stored as-is (decimal major units, e.g. 53.98).
