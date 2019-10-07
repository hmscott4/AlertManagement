# AlertManagement
Manage SCOM Alerts

Management Pack for Alert Workflow

1. Includes owner assignment of alert based on Management Pack and custom rules (configurable).
2. Includes configuration for handling alert storms

Requires the following custom Alert Resolution States:

------------------------------------------------------------------------
| State | Description    | Notes                                       |
------------------------------------------------------------------------
|   5   | Owner Assigned | Transient Alert State; persists < 5 minutes |
------------------------------------------------------------------------
|  15   | Verified       | Persistent Alert State; the new "New"       |
------------------------------------------------------------------------
|  18   | Alert Storm    | Persistent Alert State                      |
------------------------------------------------------------------------
