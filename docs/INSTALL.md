# Installing the Humanitix → Salesforce Connector

## Prerequisites

- A Salesforce org (Enterprise, Unlimited, Developer, or a scratch/sandbox). The
  connector uses **Campaigns** and **Campaign Members**, so the org must have the
  Campaigns feature and the syncing user must be a **Marketing User** (see
  [CONFIGURATION.md](CONFIGURATION.md)).
- A **Humanitix API key**: create one in Humanitix under *Account → Advanced →
  API Keys*.

## Option A: Install the unlocked package (recommended for most orgs)

Version 1.3.1 (`04tOb000002TPebIAG`):

[![Install in Sandbox](https://img.shields.io/badge/Install%20in%20Sandbox-5A6E7F?style=for-the-badge&logo=salesforce&logoColor=white)](https://test.salesforce.com/packaging/installPackage.apexp?p0=04tOb000002TPebIAG)
[![Install in Production](https://img.shields.io/badge/Install%20in%20Production-00A1E0?style=for-the-badge&logo=salesforce&logoColor=white)](https://login.salesforce.com/packaging/installPackage.apexp?p0=04tOb000002TPebIAG)

1. Click **Install in Production** (production, Developer Edition or Trailhead
   Playground) or **Install in Sandbox**. The buttons above always point at the
   current release; the same URL is published on the
   [latest release](../../releases).
2. Choose **Install for Admins Only** (you grant access via the permission set).
3. After install, continue with [Post-install setup](#post-install-setup).

Or from the Salesforce CLI:

```bash
sf package install --package 04tOb000002TPebIAG --wait 20 --security-type AdminsOnly --target-org <alias>
```

> **No-namespace note:** this package has no namespace, so its components install
> into your org's default namespace. Every component is prefixed `Humanitix` /
> `Humanitix_*__c` to avoid collisions. If you already have components with those
> exact API names, review before installing.

## Option B: Deploy from source (scratch org / sandbox / dev org)

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
deleting it; deleted records are treated as missing and re-created on the
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
2. **Enter your API key.** Open the *Humanitix Integration* app → *Humanitix
   Setup* tab → **Connection** tab, paste your Humanitix API key, and click
   **Save Key**. If your org will not let the page save the key, enter it in
   Setup instead; the fallback steps and the Marketing User requirement are both
   in **[CONFIGURATION.md](CONFIGURATION.md)**.
3. **Verify the connection.** Still on the **Connection** tab, click **Test
   Connection**. A green result showing `HTTP 200` confirms both the key and the
   callout principal. `401` or `403` means the key is wrong or the permission set
   isn't assigned. From the CLI, the same probe runs as anonymous Apex:

   ```bash
   echo "System.debug(new HumanitixHttpClient().get('/v1/events?page=1').getStatusCode());" | sf apex run --target-org <your-org>
   ```

4. **Run the sync.** From the *Humanitix Setup* tab, click **Run Sync Now**, or
   schedule a recurring run.

## Upgrading / installing over an existing source deploy

Installing the package into an org that already runs the connector from a
source deploy **adopts** the existing components into the package. One
casualty to expect: replacing the `HumanitixAPI` external credential
definition **deletes the manually-entered `ApiKey` authentication parameter**,
and every callout then fails with
`Field HumanitixAPI.ApiKey does not exist. Check spelling.` (from 1.3.1 the
run stops on its first step with *No Humanitix API key is saved*, and the
Dashboard checklist shows the same). After the install,
re-enter the parameter (step 2 of Post-install setup) before running a sync.
Normal package-to-package upgrades only touch the external credential if its
definition changed in the new version, so the parameter usually survives those.

## Troubleshooting the install

Start with the **Ready to sync** checklist on the *Humanitix Setup* tab's
**Dashboard**: it checks the API key, the connection, the Marketing User and
permission set for the users who run the sync, and the schedule, and says what
to do for any item that fails.

If the install itself fails:

- **The connector was already deployed from source.** Installing over a source
  deploy normally adopts the existing components (see the section above, and
  re-enter the API key afterwards). If the install stops with an error, it names
  the component it could not install. A component that was changed in the org in
  a way the package cannot apply, for example a field whose type was changed,
  must be changed back to match the package, or removed, before you install
  again.
- **Installing an older version over a newer one.** A package cannot be
  downgraded. Install the current version instead. Going back to an older
  version means uninstalling first, which deletes the connector's objects and
  their data.
- **Right after deleting connector fields.** Salesforce keeps a deleted custom
  field, and its API name, until it is erased, so a package field of the same
  name cannot be created. In Setup, open **Object Manager**, the object,
  **Fields & Relationships**, then **Deleted Fields**, and **Erase** the field.
  Then install again.

## Uninstalling

Setup → Installed Packages → **Uninstall**. Custom objects and the fields added to
standard objects are removed; the Campaign/Contact records the connector created
remain (they are standard records).
