# Install Management Pack

- Download the latest release of the management pack from [https://github.com/hmscott4/AlertManagement/releases](https://github.com/hmscott4/AlertManagement/releases)
- [Import the management pack](https://docs.microsoft.com/system-center/scom/manage-mp-import-remove-delete?#import-a-management-pack-from-disk)
- Add resolution states
  1. In the Operations Manager Console
  1. Select **Monitoring**
  1. Expand **Alert Management**
  1. Select **Root Management Servers**
  1. Expand the task pane on the right-hand side
  1. Click **Add Alert Management Resolution States**
- Deploy the configuration files
  1. In the Operations Manager Console
  1. Select **Monitoring**
  1. Expand **Alert Management**
  1. Select **Root Management Servers**
  1. Expand the task pane on the right-hand side
  1. Click **Create Alert Management Config Files**
  1. Click **Override**
  1. Enter a path for the **Destination**
  1. Click **Override**
  1. Click **Run**
- Configure the [**Assign SCOM Alerts**](Assign-Alerts) rule.
- Configure the [**Escalate SCOM Alerts**](Escalate-Alerts) rule.
