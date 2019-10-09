# AlertManagement

##Management Pack for Alert Workflow

1. Includes owner assignment of alert based on Management Pack and custom rules (configurable).
2. Includes configuration for handling alert storms

## Basic Workflow
The following table summarizes the basic alert workflow using the management pack:
------------------------------------------------------------------------
| Old State | New State | Comment                                      |
|:---------:|:---------:|:---------------------------------------------|
| 0         | 5         | Owner assigned to alert; updated every minute|
| 5         | 247       | Rule-based alerts updated to "Awaiting Evidence"|
| 5         | 15        | Monitor-based alerts updated to "Verified"   |
| 0,5       | 18        | Alerts updated to "Alert Storm" based on count.|
| 247       | 15        | Rule-based alerts updated to "Verified" if repeat count increases.|
-----------------------------------------------------------------------

0=New
5=Owner Assigned
15=Verified
18=Alert Storm

## Custom Resolution States
Requires the following custom Alert Resolution States:
------------------------------------------------------------------------
| State | Description    | Notes                                       |
|:-----:|:---------------|:--------------------------------------------|
|   5   | Owner Assigned | Transient Alert State; persists < 5 minutes |
|  15   | Verified       | Persistent Alert State; the new "New"       |
|  18   | Alert Storm    | Persistent Alert State                      |
