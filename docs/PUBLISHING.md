# Publishing the unlocked package (maintainers)

This project is distributed as a **2GP unlocked package** (no namespace) — versioned,
upgradeable, click-installable. This guide creates and promotes a version so anyone
can install it from a URL, the same way projects like
[NebulaLogger](https://github.com/jongpie/NebulaLogger) do.

> Not unmanaged, not managed: **unlocked** is the recommended distribution type —
> upgradeable and namespace-free, unlike a legacy unmanaged snapshot, and without the
> namespace/lock-in of a managed package.

## One-time setup

1. In your Dev Hub org: **Setup → Dev Hub → Enable Dev Hub**, then enable
   **Unlocked Packages and Second-Generation Managed Packages**.
2. Authenticate the CLI:
   ```bash
   sf org login web --set-default-dev-hub --alias devhub
   ```
3. Register the package (writes a `packageAliases` block into `sfdx-project.json`):
   ```bash
   sf package create \
     --name "Humanitix Salesforce Connector" \
     --package-type Unlocked \
     --path force-app \
     --target-dev-hub devhub
   git add sfdx-project.json
   git commit -m "chore: register unlocked package"
   git push
   ```

## Each release

```bash
# 1. Create a version (04t… id; beta). --code-coverage is required to promote.
sf package version create \
  --package "Humanitix Salesforce Connector" \
  --installation-key-bypass \
  --code-coverage \
  --wait 90 \
  --target-dev-hub devhub
git add sfdx-project.json && git commit -m "chore: package version" && git push

# 2. Install-test the beta in a throwaway scratch org
sf org create scratch -f config/project-scratch-def.json -a insttest -d 1 -w 10
sf package install --package 04t... --target-org insttest --wait 20 --no-prompt
sf apex run test -o insttest -l RunLocalTests -c -r human
sf org delete scratch -o insttest --no-prompt

# 3. Promote to released (production-installable; needs >=75% Apex coverage)
sf package version promote --package 04t... --target-dev-hub devhub --no-prompt

# 4. List versions any time
sf package version list --target-dev-hub devhub
```

Then update the install links in [`README.md`](../README.md) with the promoted
`04t…` id (Production = `login.salesforce.com`, Sandbox = `test.salesforce.com`).

## Versioning

Bump `versionNumber` in `sfdx-project.json` for each release — the trailing `.NEXT`
auto-increments the build number (e.g. `1.0.0.NEXT` → `1.0.0.1`, `1.0.0.2`). For a new
minor/major, set it explicitly, e.g. `1.1.0.NEXT`.

## Automated releases (CI)

[`.github/workflows/release.yml`](../.github/workflows/release.yml) runs
**create → install-test → promote → publish install URL** automatically when you
publish a GitHub Release, once:

1. The one-time `sf package create` is done and the alias is committed, and
2. The **`DEVHUB_SFDX_URL`** repo secret is set:
   ```bash
   sf org display --target-org devhub --verbose --json   # copy the "sfdxAuthUrl" value
   ```
   Add it under **Settings → Secrets and variables → Actions**.

## (Optional) also offering a managed package

If you later want an AppExchange-style **managed** package alongside the unlocked one
(like NebulaLogger's second option), that requires a namespaced packaging org and a
separate `sf package create --package-type Managed` lineage. Managed install URLs add
`&mgd=true`. This is a bigger commitment (permanent namespace, security review for
AppExchange) and is not needed for open distribution.
