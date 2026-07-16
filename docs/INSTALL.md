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

## Post-install setup

1. **Assign the permission set.** Setup → Permission Sets →
   **Humanitix Integration Admin** → *Manage Assignments* → add the user(s) who
   will run the sync. This also activates the API callout principal.
2. **Enter your API key** and confirm the running user is a Marketing User —
   see **[CONFIGURATION.md](CONFIGURATION.md)**.
3. **Smoke-test and run** — from the *Humanitix Integration* app → *Humanitix
   Setup* tab, click **Run Sync Now**, or schedule a recurring run.

## Uninstalling

Setup → Installed Packages → **Uninstall**. Custom objects and the fields added to
standard objects are removed; the Campaign/Contact records the connector created
remain (they are standard records).
