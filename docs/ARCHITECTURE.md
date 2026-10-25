# Architecture

## On the customer's network

LoNSeMonSy is one Ubuntu machine on the local network. Nothing else is required.

![How it fits in your network](./customer_site_architecture.png)

## Inside the appliance

```mermaid
flowchart LR
    agents["Wazuh agents<br/>on servers and PCs"] -->|logs| wazuh
    subgraph box["LoNSeMonSy appliance (Ubuntu)"]
      wazuh["Wazuh<br/>manager + indexer"]
      suri["Suricata"] -->|scan alerts| wazuh
      nax["NetAlertX"]
      influx["InfluxDB"]
      graf["Grafana"]
      wazuh --> graf
      nax --> graf
      influx --> graf
      fw["ufw firewall"]
    end
    graf -->|dashboard| owner["Owner's browser"]
    graf -->|email| mail["Alert email"]
    wazuh -->|block attacker IP| fw
```

| Port | Service | Who connects |
|---|---|---|
| 3000 | Grafana | the owner's browser |
| 1514 / 1515 | Wazuh | agents on monitored machines |
| 443 | Wazuh dashboard (advanced) | IT person |
| 20211 | NetAlertX | IT person |

Everything else stays on the appliance itself.
