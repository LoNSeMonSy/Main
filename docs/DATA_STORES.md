# Why three data stores (and why that's the right call)

Short answer: **each off-the-shelf tool comes with its own database built in — you don't
choose it.** So we don't try to force everything into one store. We centralize the *view*
(Grafana), not the *storage*. That's a normal, mature pattern (sometimes called "polyglot
persistence"): use the store that fits each kind of data, and unify at the top.

## The three stores

| Store | Holds | Shape of that data | Who owns it |
|---|---|---|---|
| **InfluxDB** | backup history, storage %, audit log | **time-series** — "a number at a point in time" | **us** (we chose it, we write to it) |
| **OpenSearch** | Wazuh security alerts | **search documents** — rich JSON you full-text search & filter | **Wazuh** (bundled, required) |
| **SQLite** | NetAlertX device inventory | **a small relational table** — ~dozens of rows | **NetAlertX** (bundled) |

## "Why does Wazuh need OpenSearch? Why not InfluxDB?"

Two reasons:

1. **We don't get a choice.** Wazuh is built *on* OpenSearch (it's forked from
   Elasticsearch). You cannot tell Wazuh "store alerts in InfluxDB instead" — it's wired to
   its own engine. Swapping it would mean rewriting Wazuh, which defeats the whole point of
   using an off-the-shelf tool.
2. **It's the right shape anyway.** A Wazuh alert is a big JSON document, and the useful
   questions are search questions: *"show every SSH failure from IP X across all machines in
   the last week."* That's what a search engine (OpenSearch) is built for. InfluxDB is built
   for *"this metric's value over time"* — it's great at graphs, bad at searching documents.

## "Why does NetAlertX use SQLite instead of InfluxDB, to centralize?"

Same two reasons, smaller scale:

1. **Bundled.** NetAlertX ships with SQLite. It's not a knob we set.
2. **Right shape.** A device list is a small, bounded table (an IP, a name, a vendor, first/
   last seen — a few dozen rows). A single-file relational table is perfect and needs zero
   maintenance. Putting a slowly-changing lookup table into a time-series database would be
   the *wrong* tool — InfluxDB is optimized for high-volume timestamps, not "look up the row
   for this MAC address."

## "But I wanted it centralized"

The instinct is right — the user *should* feel like it's one system. But the place to
centralize is the **presentation layer, not the database.** Grafana reads all three stores
and shows them as one dashboard. To the customer it *is* one thing. Forcing one physical
database underneath would mean fighting (or rewriting) the tools and using the wrong storage
for two of the three data shapes — more work, worse result.

Same principle as our UI decision: don't force one tool to do everything — unify at the top.

## The trade-off (be honest in the demo)

- **Cost:** three things to back up, and OpenSearch is a RAM hog (the main reason the
  appliance needs 8 GB).
- **Benefit:** every tool runs exactly as its makers intended (no rewrites, no fragile
  hacks), each kind of data sits in a store built for it, and Grafana still makes it one pane.

**Demo one-liner:** *"Three fit-for-purpose stores — time-series, search, and relational —
unified into a single view in Grafana. We centralized what the user sees, not where the bytes
live."*
