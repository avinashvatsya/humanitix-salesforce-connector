# Configuration

## 1. Enter your Humanitix API key (required)

The key is stored encrypted in an **External Credential**, never in code or
metadata. You enter it once.

### From the Humanitix Setup tab (recommended)

1. Open the *Humanitix Integration* app and go to the **Humanitix Setup** tab.
2. Select the **Connection** tab.
3. Paste your Humanitix API key into **Humanitix API Key**, then click **Save Key**.
4. Click **Test Connection**. A green result showing `HTTP 200` means you are
   connected.

Saving from this page writes to the external credential principal, which in some
orgs requires the **Customize Application** permission. If the page reports that
it cannot save or read the key, use the manual path below. The manual path always
works.

### If the page cannot save the key in your org

Enter the key directly in Setup:

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

### Verifying from the command line

**Test Connection** on the Connection tab is the quickest check. If you prefer
Apex, run the same probe from **Setup → Developer Console → Debug → Open Execute
Anonymous**:

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

### From the Humanitix Setup tab (recommended)

Open the **Humanitix Setup** tab and select **Sync Settings**. The form edits the
same `Default` record described below: **Page Size**, **Enabled Resources**,
**Future events only**, **Ticket Status Filter**, **Max Retries**, **Retry Delay
Minutes**, **Since Mode** and **Named Credential Name**. If your org has no
settings record yet, the form shows the values the connector is currently using
and saving creates the record.

**Save Settings** starts a Custom Metadata deployment, which Salesforce runs
asynchronously, so a save takes a few seconds rather than being instant. The page
waits for that deployment and then confirms it, or shows the error the deployment
reported. If the page tells you the deployment is taking longer than expected,
check **Setup → Deployment Status**.

The **Sync Enabled** toggle at the top of the same tab is the kill switch, and it
is saved on its own, not through that deployment: see
[Kill switch](#4-kill-switch).

### From Setup (fallback and advanced)

The record can always be edited directly, and this is the only way to change the
settings the form does not show, such as **Consecutive Failure Threshold**. Edit
**Setup → Custom Metadata Types → Humanitix Sync Setting → Manage Records →
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

**Humanitix Setup → Sync Settings → Sync Enabled** stops all sync activity.
Unlike the rest of that form it is saved on its own and takes effect immediately:
scheduled and manual runs will not start, and a run already in flight stops at
its next step. Switch it back on to let runs start again.

The toggle is the org default of the **Humanitix Sync Toggle** custom setting, so
you can also set it from **Setup → Custom Settings → Humanitix Sync Toggle →
Manage → New** (org default) → uncheck **Sync Enabled**. Sync counts as enabled
when no record exists.

## 5. Running the sync

- **On demand:** *Humanitix Integration* app → *Humanitix Setup* tab →
  **Dashboard** → **Run Sync Now**. The same tab lists the recent runs with their
  status and totals.
- **Scheduled:** *Humanitix Setup* tab → **Schedule**, described below.
- **From a Flow / Agentforce:** add the **Run Humanitix Sync** invocable action.

Monitor runs on the **Humanitix Sync Logs** tab — each run has a header (status,
totals) and per-resource/per-event entries with any error messages.

### Scheduling from the Schedule tab

The **Schedule** tab has two settings and creates the scheduled jobs for you:

- **Delta sync interval:** Off, every 15 minutes, 30 minutes, 1 hour, 2 hours,
  4 hours, 6 hours or 12 hours. Intervals under an hour need one scheduled job
  per fire minute, so the tab creates up to four jobs, named **Humanitix Delta
  Sync 1** through **Humanitix Delta Sync 4**.
- **Daily full sync time:** a 24 hour `HH:mm` time creates one job named
  **Humanitix Daily Full Sync**. Leave it empty for no daily run.

Interval runs are always incremental and the daily run always re-pulls
everything, whatever **Since Mode** is set to. Manual runs and Flow runs keep
following **Since Mode** (section 3), so the daily job is your safety net if
incremental sync ever misses an edit.

Also worth knowing:

- Cron times use the Salesforce timezone of the user who saves the schedule.
- A run still in flight when the next fire time arrives is skipped, so runs never
  stack up behind a slow one. The tab warns you before you save if the daily time
  falls on the same minute as an interval run.
- **Current jobs** lists the jobs the tab manages, with their cron expression,
  next run time and state. If those jobs stop matching the saved schedule, the
  tab shows a **Repair schedule** button that recreates them.
- Any other scheduled job whose name starts with `Humanitix`, for example a
  **Humanitix Nightly Sync** job that earlier versions of these docs had you
  create by hand, is listed separately as scheduled outside the page. Cancel it
  in **Setup → Scheduled Jobs** so it does not trigger a second, duplicate run.

### Advanced: scheduling from Apex

Scheduling from Execute Anonymous still works:

```apex
HumanitixSyncScheduler.schedule('Humanitix Nightly Sync', '0 0 2 * * ?'); // daily 02:00
```

A job created this way follows **Since Mode** rather than being forced full or
incremental, and the Schedule tab reports it as a job it does not manage.

## 6. Changing what maps where

All object/field bindings live in Custom Metadata and are fully remappable with no
code, either from the **Mappings** tab of *Humanitix Setup* or in Setup itself.
See **[FIELD-MAPPING.md](FIELD-MAPPING.md)**.

### Choosing how buyer Contacts are matched

The `Order_to_Contact` mapping ships with Match Strategy `MatchByFields` on
`Email` and Update Mode `BlanksOnly`: buyers are de-duplicated against existing
Contacts by email, missing details are filled in, and values your org already
has are never overwritten. To let Humanitix data overwrite Salesforce
(`Always`), to leave matched Contacts completely untouched (`Never`), or to
always create new Contacts and let your own duplicate rules handle merging
(`AlwaysCreate`), edit the `Humanitix Object Mapping > Order_to_Contact` Custom
Metadata record — see [FIELD-MAPPING.md](FIELD-MAPPING.md#update-modes).

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

