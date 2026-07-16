# Humanitix → Salesforce Connector

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Salesforce](https://img.shields.io/badge/Salesforce-Unlocked%20Package-00A1E0.svg)](#install)

An **open-source, read-only** connector that syncs your [Humanitix](https://www.humanitix.com/) events, orders, tickets and tags into Salesforce. Ships as a **2GP unlocked package (no namespace)** so any org can install it, and every field-to-object binding is **remappable with no code** via Custom Metadata.

> ⚠️ This is an independent, community-built integration. It is **not** affiliated with, endorsed by, or sponsored by Humanitix or Salesforce.

---

## Why this exists

Humanitix already offers an official managed connector. This project is a free, transparent, **more configurable** alternative:

| | Official connector | This connector |
| --- | --- | --- |
| Source | Closed managed package | **Open source, forkable** |
| Field mapping | Fixed | **Remappable via Custom Metadata (no code)** |
| Incremental sync | Full pulls | **Incremental `since` cursors** |
| Standard objects | Campaign, Contact | **Campaign, Contact, Campaign Member** (+ optional Lead / Account) |
| Tags | — | **Synced** |
| Faithful staging objects | Yes | **Yes** (Event, Order, Ticket, Ticket Type, Date, Attributes) |
| Observability | — | **Sync logs, retries, per-event fault isolation** |
| Auth | OAuth (Humanitix-hosted) | **API key via External Credential** |

## What it does

- **One-way sync** — Humanitix → Salesforce. It never writes back to Humanitix.
- Pulls **Events, Orders, Tickets, Tags** (plus nested Ticket Types, Event Dates, and checkout question responses).
- Writes a **faithful custom-object layer** (system of record) *and* maps into **standard objects** (Campaign / Contact / Campaign Member) by default.
- **Repoint any field** to your own object/field by editing Custom Metadata — no Apex changes.
- Runs on a **schedule**, **on demand**, or from a **Flow / Agentforce** action, with full **sync logs**.

## How it works

```
Humanitix REST API  ──(x-api-key via Named/External Credential)──►  Sync engine (Queueable chain, incremental `since`)
                                                                          │
                                                        CMT-driven mapping engine (JSON path → field, transforms)
                                                                          │
                        ┌─────────────────────────────────────────────────┴───────────────────────────────┐
              Custom staging objects (faithful)                                    Standard objects (CRM, remappable)
        Humanitix_Event__c / Order__c / Ticket__c / …                         Campaign / Contact / Campaign Member
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design.

## <a name="install"></a>Install

Prerequisites, package install, and the exact post-install steps (entering your API key, assigning the permission set, scheduling the sync) are in **[docs/INSTALL.md](docs/INSTALL.md)** and **[docs/CONFIGURATION.md](docs/CONFIGURATION.md)**.

> **No-namespace note:** this package installs its components into your org's default namespace. All API names are prefixed `Humanitix` / `Humanitix_*__c` to avoid collisions, but if you already have components with those names, review before installing.

## Configure the mapping

The default mappings target standard objects. To send any Humanitix field to a different object or field, edit the `Humanitix Object Mapping` / `Humanitix Field Mapping` Custom Metadata records — see **[docs/FIELD-MAPPING.md](docs/FIELD-MAPPING.md)**.

## Develop / contribute

See [CONTRIBUTING.md](CONTRIBUTING.md). Quick start:

```bash
npm install
sf org create scratch -f config/project-scratch-def.json -a htx-dev -d 7
sf project deploy start -o htx-dev
sf org assign permset -n Humanitix_Integration_Admin -o htx-dev
sf apex run test -o htx-dev -l RunLocalTests -c -r human
npm run test:unit
```

## License

[MIT](LICENSE).
