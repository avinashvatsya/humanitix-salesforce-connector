# Contributing

Thanks for helping improve the Humanitix → Salesforce connector! It is an
open-source **unlocked package (no namespace)**; contributions of code, mappings,
docs, and bug reports are all welcome.

## Prerequisites

- Node 20 LTS
- Salesforce CLI v2 (`npm install --global @salesforce/cli`; the command is `sf`)
- A Dev Hub (a free [Developer Edition](https://developer.salesforce.com/signup)
  works — enable **Dev Hub** and **Unlocked & Second-Generation Managed Packages**
  under Setup)

## Local setup

```bash
npm install
sf org login web --set-default-dev-hub --alias devhub
./scripts/setup.sh htx-dev        # creates a scratch org, deploys, assigns the permset
```

## Running tests

```bash
npm run test:unit                 # LWC Jest tests
sf apex run test -o htx-dev -l RunLocalTests -c -r human   # Apex tests + coverage
npm run prettier:verify           # formatting
```

## Metadata is generated — don't hand-edit fields

To keep field-level security in the permission sets perfectly in sync with the
fields that exist, objects/fields/permission sets are generated from a single
registry. **If you add or change a custom object or field, edit the generator and
re-run it** rather than editing the XML by hand:

```bash
python3 scripts/dev/generate-metadata.py          # objects, fields, CMTs, permission sets
python3 scripts/dev/generate-default-mappings.py  # default Object/Field Mapping CMT records
```

Hand-authored metadata (Apex, LWC, credentials, app, tabs, flexipage) is not
touched by the generators.

## Changing the default field mappings

The connector's behaviour is driven by Custom Metadata, not hard-coded Apex. To
change what maps where, edit `scripts/dev/generate-default-mappings.py` and re-run
it, or (for a specific org) edit the `Humanitix Object Mapping` / `Humanitix Field
Mapping` records directly. See [docs/FIELD-MAPPING.md](docs/FIELD-MAPPING.md) and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Pull requests

- Keep changes focused; follow the existing Apex/LWC style (Prettier enforced).
- Add or update tests. Apex must keep org-wide coverage ≥ 75% (we aim higher).
- The PR template checklist must pass; CI runs Prettier, Jest, and a full scratch-org
  deploy + Apex test run on every PR.

## Reporting security issues

Please do not open a public issue for security vulnerabilities. See
[SECURITY.md](SECURITY.md).
