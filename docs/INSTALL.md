# Installing the Humanitix → Salesforce Connector

## Prerequisites

- A Salesforce org (Enterprise, Unlimited, Developer, or a scratch/sandbox). The
  connector uses **Campaigns** and **Campaign Members**, so the org must have the
  Campaigns feature and the syncing user must be a **Marketing User** (see
  [CONFIGURATION.md](CONFIGURATION.md)).
- A **Humanitix API key** — create one in Humanitix under *Account → Advanced →
  API Keys*.

## Option A — Install the unlocked package (recommended for most orgs)

1. Open the install URL published on the [latest release](../../releases) (looks
   like `https://login.salesforce.com/packaging/installPackage.apexp?p0=04t…`).
   Use `test.salesforce.com` for sandboxes.
2. Choose **Install for Admins Only** (you grant access via the permission set).
3. After install, continue with [Post-install setup](#post-install-setup).

> **No-namespace note:** this package has no namespace, so its components install
> into your org's default namespace. Every component is prefixed `Humanitix` /
> `Humanitix_*__c` to avoid collisions. If you already have components with those
> exact API names, review before installing.

## Option B — Deploy from source (scratch org / sandbox / dev org)

```bash
git clone <this-repo> && cd humanitix-salesforce-connector
npm install
sf org login web --set-default-dev-hub --alias devhub     # Dev Hub, for scratch orgs
./scripts/setup.sh htx-dev                                 # scratch org + deploy + permset
```

Or deploy into an existing org:

```bash
sf project deploy start --target-org <your-org>
sf org assign permset --name Humanitix_Integration_Admin --target-org <your-org>
```

After a source deploy, seed the default mapping metadata (package installs do
this automatically the first time the *Humanitix Setup* tab is opened):

```bash
echo "System.enqueueJob(new HumanitixMappingSeeder());" | sf apex run --target-org <your-org>
```

The seeding deployment is asynchronous; within a minute you should see 13
Humanitix Object Mapping and 159 Humanitix Field Mapping records under
**Setup → Custom Metadata Types**. Re-running the seeder is safe: it only
creates records that don't already exist, so your edited mappings are never
overwritten. (To turn a default mapping off, untick **Is Active** rather than
deleting it — deleted records are treated as missing and re-created on the
next upgrade.)

Seeding is about *customization*, not function: while an org has no mapping
records at all, the connector automatically runs on the same built-in defaults
(from the packaged `Humanitix_Default_Mappings` static resource), so a sync
started before seeding finishes still maps everything. Once any mapping record
exists, the org's records are authoritative.

## Post-install setup

1. **Assign the permission set.** Setup → Permission Sets →
   **Humanitix Integration Admin** → *Manage Assignments* → add the user(s) who
   will run the sync. This also activates the API callout principal.
2. **Enter your API key** and confirm the running user is a Marketing User —
   see **[CONFIGURATION.md](CONFIGURATION.md)**.
3. **Smoke-test and run** — from the *Humanitix Integration* app → *Humanitix
   Setup* tab, click **Run Sync Now**, or schedule a recurring run.

## Upgrading / installing over an existing source deploy

Installing the package into an org that already runs the connector from a
source deploy **adopts** the existing components into the package. One
casualty to expect: replacing the `HumanitixAPI` external credential
definition **deletes the manually-entered `ApiKey` authentication parameter**,
and every callout then fails with
`Field HumanitixAPI.ApiKey does not exist. Check spelling.` (the sync retries
silently, so check Setup → Apex Jobs if runs seem stuck). After the install,
re-enter the parameter (step 2 of Post-install setup) before running a sync.
Normal package-to-package upgrades only touch the external credential if its
definition changed in the new version, so the parameter usually survives those.

## Uninstalling

Setup → Installed Packages → **Uninstall**. Custom objects and the fields added to
standard objects are removed; the Campaign/Contact records the connector created
remain (they are standard records).
