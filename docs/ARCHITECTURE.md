# Architecture

## On the customer's network

LoNSeMonSy is one Ubuntu machine on the local network. Nothing else is required. A switch and cloud backup are optional.

```mermaid
flowchart TB
    subgraph net["Internet"]
      gh["GitHub<br/>install + updates"]
      mail["Email<br/>alerts to the owner"]
      cloud["Cloud backup<br/>(optional, planned)"]
    end
    router["Router / modem<br/>customer's own firewall"]
    switch["Network switch (optional)"]
    pcs["Servers and PCs<br/>Wazuh agent"]
    app["<b>LoNSeMonSy</b><br/>Ubuntu server, mini PC or VM"]
    other["Other devices<br/>printers, phones, cameras"]
    owner["Owner or IT person<br/>browser"]

    net --- router --- switch
    switch --- pcs & app & other & owner
    router -.-> cloud

    style app fill:#1D7F68,color:#fff,stroke:#1D7F68
    style cloud stroke-dasharray: 5 5
    style switch stroke-dasharray: 5 5
```

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
