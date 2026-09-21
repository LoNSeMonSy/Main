# LoNSeMonSy — Conceptual Class Diagram (Sprint 2)

This is a **conceptual** class diagram (Analysis / OOA level): it models the **data the
system stores and remembers** — the nouns of the problem domain in plain language — not the
code-level classes. Per the course, we move to specification/implementation-level diagrams
later in Design.

> Team: review this against our SRS and user stories before the demo. Adjust names/attributes
> to match our own wording — you should be able to explain every class and association.

```mermaid
classDiagram
    class Event {
        <<abstract>>
        +eventId: string
        +timestamp: datetime
        +source: string
    }
    class SecurityAlert {
        +alertId: string
        +sourceIp: string
        +alertType: string
        +severity: enum
        +severityInt: int, 0
        +ruleId: string
        +description: string
        +create()
        +retrieve()
    }
    class AuditEvent {
        +action: string
        +actor: string
        +target: string
        +targetType: string
        +origin: string
        +message: string
        +oldValue: string
        +newValue: string
        +create()
        +retrieve()
    }
    class DetectionRule {
        +ruleId: string
        +level: int, 0
        +description: string
        +frequency: int, 0
        +timeframe: int, 0
        +mitreId: string
        +group: string
        +create()
        +update()
    }
    class MonitoredHost {
        +hostname: string
        +ipAddress: string
        +os: string
        +agentId: string
        +status: enum
        +lastSeen: datetime
        +role: string
        +register()
        +updateStatus()
    }
    class Site {
        +name: string
        +subnet: string
        +contact: string
        +addHost()
    }
    class Guest {
        +vmId: int
        +name: string
        +type: enum
        +node: string
    }
    class BackupJob {
        +upid: string
        +status: enum
        +mode: string
        +durationS: int, 0
        +storage: string
        +trigger: enum
        +percent: int, 0
        +create()
        +retrieve()
    }
    class StorageStatus {
        +datastore: string
        +totalGb: double, 0
        +usedGb: double, 0
        +availGb: double, 0
        +usagePct: double, 0
        +retrieve()
    }

    Event <|-- SecurityAlert
    Event <|-- AuditEvent
    Site "1" *-- "0..*" MonitoredHost : hosts
    MonitoredHost "1" --> "0..*" SecurityAlert : generates
    DetectionRule "1" --> "0..*" SecurityAlert : fires
    MonitoredHost "1" --> "0..*" Guest : runs
    Guest "1" --> "0..*" BackupJob : backed up by
    Site "1" o-- "0..*" StorageStatus : reports
    MonitoredHost "1" --> "0..*" AuditEvent : subject of
```

## What each class stores and why

| Class | Purpose (data at rest) | Backed by |
|---|---|---|
| **Event** (abstract) | Common fields every recorded event shares (id, time, source). Generalization for the "kind of" events below. | — |
| **SecurityAlert** | A detection raised by the SIEM. | Wazuh `wazuh-alerts-*` |
| **AuditEvent** | Administrative history — who did what to which target. | `audit_log` measurement |
| **DetectionRule** | The rules that decide when an alert fires (threshold, severity, wording). | Wazuh rules + our `local_rules.xml` |
| **MonitoredHost** | A machine the SIEM watches (a Wazuh agent). | Wazuh agent registry |
| **Site** | The customer deployment the hosts belong to. | Deployment config |
| **Guest** | A VM/container that gets backed up. | Proxmox / PBS |
| **BackupJob** | A backup run and its outcome/progress. | `pbs_backup_main` / `pbs_backup_progress` |
| **StorageStatus** | Backup storage capacity over time. | `pbs_storage_stats` |

## Relationships (the associations to explain in the demo)

- **Generalization** (`<|--`): `SecurityAlert` and `AuditEvent` are *kinds of* `Event` — they
  share id/timestamp/source.
- **Composition** (`*--`): a `Site` is made of its `MonitoredHost`s — a host does not exist
  outside a site.
- **Aggregation** (`o--`): a `Site` collects `StorageStatus` readings, which can exist
  independently.
- **Association** (`-->`): a `MonitoredHost` *generates* many `SecurityAlert`s; a
  `DetectionRule` *fires* many `SecurityAlert`s; a `Guest` is *backed up by* many `BackupJob`s.

Each piece of data lives in exactly one class (e.g. `sourceIp` only on `SecurityAlert`, host
identity only on `MonitoredHost`), per the single-source-of-truth rule.
