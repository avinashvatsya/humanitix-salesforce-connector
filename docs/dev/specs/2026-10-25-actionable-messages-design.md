# Actionable Messages (1.3.1): Design

**Date:** 2026-10-25
**Status:** Designed from the 1.3.1 brief (a patch release). Target: package
version 1.3.1 (`1.3.1.NEXT`, "Version 1.3.1").

## Context and goal

Admins today see raw platform and HTTP text when something is wrong, and some
problems are not visible at all:

- A missing API key surfaces as `Max retries exceeded (HTTP null)` after five
  silent re-enqueues (`HumanitixSyncQueueable.runStep` catches the
  `CalloutException` and classifies the null status as RETRY).
- An event that was deleted in Humanitix returns 404 on its orders and tickets
  on every run, so every run is Partial. Kaipatiki production has had one such
  event (`6a8d1a50e2dfb88a6a3a40d5`) since July.
- 401/403 log one Failed entry per event and phase, all with the same raw body.
- The Dashboard has no single place that answers "is this org ready to sync?".

Goal: every failure the admin can act on is described in one plain sentence
that says what to do and where, with the raw detail kept for support.

### Decisions

- **One message vocabulary.** A new pure class `HumanitixSyncMessages` owns
  every admin-facing sentence (sync log, launcher, connection test, readiness
  checklist), so the same problem reads the same everywhere.
- **Entry format:** `<sentence> Details: <raw>`. The friendly sentence comes
  first; the raw platform text or `HTTP <status>: <body>` is appended after the
  literal ` Details: ` separator. The run summary strips everything from the
  separator on. No new field on the entry object.
- **Run-ending failures:** a missing API key and 401/403 end the whole run on
  the first occurrence (every later call would fail the same way). Other
  failures keep today's per-work-item isolation.
- **404 on an event's orders or tickets** logs a `Skipped` entry (the value
  already exists on `Humanitix_Sync_Log_Entry__c.Status__c`) and sets
  `Is_Archived__c = true` on the staged `Humanitix_Event__c`, so the Orders and
  Tickets keyset (`HumanitixSyncStateService.nextEventId`, which filters
  `Is_Archived__c = false`) skips it in this and later runs. `Skipped` does not
  degrade the run status, so a run whose only problem is a vanished event is
  Success.
- **Run summary on the header.** `HumanitixSyncLogService.finalizeRun` fills the
  existing, so far unused `Humanitix_Sync_Log__c.Error_Summary__c` with the
  distinct friendly sentences of the run's problem entries. The Dashboard runs
  table shows it as a **Reason** column. No new fields in this release.
- **Readiness checklist** is a new child component on the Dashboard tab, backed
  by one Apex call that runs five checks. It runs one live callout (the
  connection check) each time the Dashboard loads or the admin clicks Refresh.
- **Launcher pre-check:** `HumanitixSyncLauncher.start` refuses to start when
  the key is known to be missing (`KeyStatus.statusKnown && !keySaved`). When
  the status cannot be read (ConnectApi unavailable to the running user), it
  starts as today and the queueable fast-fail covers it.

### Alternatives considered

- *New `Friendly_Message__c` field on the entry* instead of the `Details:`
  convention: cleaner to query, but adds packaged schema and FLS for a patch
  release. Rejected; the separator is enough for the summary and readable on
  the record page.
- *A new `Skipped_At__c` or `Not_Found__c` field on `Humanitix_Event__c`*
  instead of reusing `Is_Archived__c`: would survive a later events page that
  maps `isArchived = false` back over it. Rejected for now: a deleted event no
  longer appears in the events listing, and if it ever did, the next orders
  call logs another harmless `Skipped` entry and archives it again.
- *Checklist computed from the last run* instead of a live callout: no
  callout, but stale and silent before the first run. Rejected.

## Feature 1: Message vocabulary (`HumanitixSyncMessages`)

A `public with sharing` class of static methods, no state, no DML. Exact texts:

| Method | Sentence |
| --- | --- |
| `MISSING_KEY` (constant) | `No Humanitix API key is saved. Add it on the Connection tab.` |
| `isMissingCredential(String platformMessage)` | true when the message contains `does not exist` (same rule as `HumanitixSyncSettingsController.calloutFailureMessage`, which now delegates here) |
| `authRejected(Integer status)` | `Humanitix rejected the API key (HTTP 401). Check the key on the Connection tab and that the user running the sync has the Humanitix Integration Admin permission set.` |
| `eventNotFound()` | `This event no longer exists in Humanitix and was skipped. Later runs skip it too.` |
| `busy(Integer status, Integer attempts)` | `Humanitix was busy or unavailable (HTTP 503) after 6 attempts. The next run tries again.` |
| `unreachable(Integer attempts)` | `Humanitix could not be reached after 6 attempts. The next run tries again.` |
| `refused(Integer status)` | `Humanitix refused the request (HTTP 400). Send this log entry to support if it keeps happening.` |
| `unexpected()` | `Something unexpected went wrong in this step. Send this log entry to support if it keeps happening.` |
| `withDetail(String sentence, String raw)` | `sentence` when raw is blank, else `sentence + ' Details: ' + raw` |
| `sentenceOf(String entryMessage)` | the part before ` Details: ` (the whole text when absent) |

The raw detail stays on the log entry record, after the sentence.

## Feature 2: Sync engine

### Queueable (`HumanitixSyncQueueable.runStep`)

1. **CalloutException:** keep the exception message. If
   `isMissingCredential(msg)`, log a Failed entry
   `withDetail(MISSING_KEY, msg)`, record the cursor failure, and finalize the
   run immediately (no retry, no advance). Otherwise keep today's retry path.
2. **Retries exhausted:** status null logs
   `withDetail(unreachable(attempt), lastCalloutMessage)`; 429/408/5xx logs
   `withDetail(busy(status, attempt), 'HTTP ' + status + ': ' + body)`.
3. **FATAL statuses:**
   - 401/403: Failed entry `withDetail(authRejected(status), 'HTTP …: body')`,
     then finalize the run.
   - 404 in the Orders or Tickets phase: `Skipped` entry
     `withDetail(eventNotFound(), 'HTTP 404: body')`, archive the staged event
     (`update` of `Is_Archived__c = true` on the row with that
     `Humanitix_Id__c`; no-op when none), **no** `recordFailure` (the cursor is
     not promoted either), then `moveToNextEventOrPhase()`.
   - Anything else (including 404 on Tags or Events): Failed entry
     `withDetail(refused(status), 'HTTP …: body')`, advance as today.
4. **Unexpected exception in `execute`:** entry text becomes
   `withDetail(unexpected(), e.getMessage())`.

The callout always happens before the archive DML, so the "no callout after
DML" rule holds.

### Launcher (`HumanitixSyncLauncher.start`)

After the kill switch check and before the overlap guard, read
`HumanitixCredentialService.getKeyStatus()`. When `statusKnown == true` and
`keySaved == false`:

- Scheduled and Flow callers catch `LaunchException`, so their DML commits:
  write a run header (trigger source as passed) with one Failed entry
  (`MISSING_KEY`), finalize it, then throw `LaunchException(MISSING_KEY)`.
  The scheduled run therefore leaves a visible Failed run with the reason.
- Manual runs rethrow as `AuraHandledException`, so that log rolls back and the
  admin sees the sentence in the error toast instead.

`getKeyStatus()` is a ConnectApi read, not a callout, and runs before any DML.

### Run summary (`HumanitixSyncLogService.finalizeRun`)

Query the run's entries with `Status__c IN ('Failed', 'Partial', 'Skipped')`
ordered by `CreatedDate, Id`, and build `Error_Summary__c`:

- Failed: `sentenceOf(Error_Message__c)` (blank becomes `A step failed.`).
- Partial: `Some records could not be saved. Open the run's log entries for the
  row errors.`
- Skipped: counted, then one sentence `1 event no longer exists in Humanitix
  and was skipped.` / `N events no longer exist in Humanitix and were
  skipped.`

Distinct sentences in first-seen order (the skipped count last), joined with a space, abbreviated to
1,000 characters; null when there are none. Status rules are unchanged
(Skipped was never counted as degraded).

## Feature 3: Readiness checklist

### Apex: `HumanitixReadinessService`

`public static List<Item> check()` where `Item` has `@AuraEnabled` `key`,
`label`, `status` (`ok`, `error`, `warning`, `unknown`) and `message`. Each
check is wrapped so one failure becomes `unknown` without hiding the others.
Exposed as `HumanitixSyncAdminController.getReadiness()` (not cacheable).

| Key | Label | ok | not ok |
| --- | --- | --- | --- |
| `apiKey` | API key saved | `An API key is saved.` | error: `MISSING_KEY`; unknown: `The key could not be checked from this page. Use Test Connection on the Connection tab.` |
| `connection` | Connection to Humanitix | `Humanitix accepted the API key.` | skipped as unknown when the key is missing: `Add the API key first.`; 401/403: `authRejected`; 429/408/5xx (warning): `Humanitix is busy or unavailable right now. Refresh in a minute.`; missing credential exception: `MISSING_KEY`; other status: `Humanitix returned HTTP <status>. Use Test Connection on the Connection tab for details.`; other exception: `Humanitix could not be reached (<message>). Use Test Connection on the Connection tab for details.` |
| `marketingUser` | Marketing User | `<names> can create Campaigns.` | error: `<names> is not a Marketing User, so Campaigns cannot be created. Tick Marketing User on the user record in Setup, Users.` |
| `permissionSet` | Permission set | `<names> has the Humanitix Integration Admin permission set.` | error: `<names> does not have the Humanitix Integration Admin permission set. Assign it in Setup, Permission Sets.` |
| `schedule` | Schedule | `A sync schedule is set.` | warning: `No schedule is set, so syncs run only when you click Run Sync Now. Set one on the Schedule tab.` |

- The connection check is `GET /v1/events?page=1&pageSize=1` through the
  configured Named Credential.
- **Who is checked:** the current user (manual runs run as them) plus the
  owners of active Humanitix scheduled jobs (`CronTrigger` with
  `CronJobDetail.Name LIKE 'Humanitix%'` and `State IN ('WAITING',
  'ACQUIRED', 'EXECUTING')`), because scheduled runs run as the user who
  scheduled them. `<names>` lists only the failing users (or all checked users
  for the ok text), joined with `, `.
- The user checks are a pure function over `User` rows and a set of assignee
  ids, so tests do not need to insert users.
- `HumanitixConnectionController.testConnection` uses the same vocabulary for
  its exception path (`MISSING_KEY` for a missing credential).

### LWC: `humanitixReadinessChecklist`

A `lightning-card` titled **Ready to sync**, placed above **Sync Runs** in
`humanitixSetupDashboard`. On connect and on its **Refresh** button it calls
`getReadiness`. Each item shows an icon (`utility:success`, `utility:error`,
`utility:warning`, `utility:info` for unknown), the label, and the message.
A one-line header summary: `Everything is ready.` when all items are ok, else
`1 item needs attention.` / `N items need attention.` (warnings and unknowns count). A load failure shows the error
text from `errorMessage(error)` in place of the list.

### Dashboard runs table

`getRecentRuns` adds `Error_Summary__c`; the table gains a **Reason** column
(`wrapText: true`) after Errors.

## Feature 4: Install troubleshooting (docs/INSTALL.md)

A new **Troubleshooting the install** section, with only claims we can stand
behind (platform behaviour, not invented error text):

- **The connector was already deployed from source:** the install adopts the
  components; afterwards re-enter the API key (existing section, linked). If
  the install itself fails, the error names the component; a component that
  differs in type from the packaged one (for example a field whose type was
  changed in the org) must be changed back or removed before installing.
- **Installing an older version over a newer one:** packages cannot be
  downgraded. Install the current version, or uninstall first (which deletes
  the connector's objects and their data).
- **Right after deleting connector fields of the same name:** deleted custom
  fields keep their API name until they are erased. Erase them under Object
  Manager, the object, Fields & Relationships, Deleted Fields, then install.

The same section notes the Dashboard checklist as the first thing to look at
after install. Existing em dashes in INSTALL.md headings and text are replaced
while the file is being edited.

## Docs

- `docs/CONFIGURATION.md` section 5: the Ready to sync checklist, the Reason
  column, what each log sentence means (missing key, rejected key, event no
  longer exists, busy, unreachable).
- `docs/INSTALL.md`: Feature 4; the existing "Upgrading over a source deploy"
  text now says the run fails fast with the missing key sentence.

## Testing

- `HumanitixSyncMessagesTest`: every sentence, `withDetail`/`sentenceOf`
  round trip, `isMissingCredential`.
- `HumanitixSyncQueueableTest`: missing credential finalizes with one Failed
  entry and `DONE` on the first attempt; 401 ends the run; 404 on Orders logs
  Skipped, archives the event, advances, and the run finalizes Success; retries
  exhausted (503 and timeout) use the busy/unreachable sentences with details.
- `HumanitixSyncLauncherTest`: known-missing key throws with `MISSING_KEY` and
  leaves a Failed log; unknown status starts the run.
- `HumanitixSyncLogServiceTest` (or the existing log tests): summary rules,
  dedup, null when clean.
- `HumanitixReadinessServiceTest`: each item ok and not ok, user function with
  in-memory users, schedule warning, callout mocks for the connection item.
- Jest: `humanitixReadinessChecklist` (all ok, mixed, load error, refresh);
  dashboard Reason column.
- All Apex tests pass in `htx-events` with seeded mappings and do not depend on
  mapping records.

## Packaging

- `sfdx-project.json`: `1.3.1.NEXT`, "Version 1.3.1". No schema changes; new
  Apex classes are added to `ADMIN_APEX_CLASSES` and the permission sets
  regenerated.
- Kaipatiki: after upgrading, the first run that reaches event
  `6a8d1a50e2dfb88a6a3a40d5` archives it and later runs are Success.

## Out of scope

- Inline links from checklist items to the tabs (text names the tab).
- Retrying or alerting on a Failed scheduled run.
- Translating messages (Custom Labels).

## Success criteria

- No run log or checklist shows `HTTP null` or a bare platform message without
  a sentence in front of it.
- A missing API key ends a run on its first step with the missing key
  sentence.
- A vanished event no longer makes runs Partial.
- The Dashboard shows a Ready to sync checklist whose failing items say what to
  do and where.
