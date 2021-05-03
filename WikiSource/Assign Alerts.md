# Assign Alerts

The **Assign SCOM Alerts** rule executes a powershell script on a timed schedule (default is 60 seconds) which assigns alerts to owners specified in the _assign.alert.config_ file.

## Config File

The _assign.alert.config_ file is comprised of Assignments and Exceptions.

### Assignment

Assignments specify what owner should be assigned to all alerts in a management pack.

#### Assignment Attributes

- **ID**: A numerical ID for the assignment.
- **Name**: A logical group which is applied to the rules. This is used strictly for organizational purposes.
- **Owner**: The name of the owner to assign to the alert.
- **enabled**: Specifies if the rule is processed or not.

#### Assignment Elements

- **ManagementPack**: An element which describes a management pack

##### ManagementPack Attributes

- **Name**: The name (not the display name) of the management pack.

#### Assignment Examples

##### Enabled Assignment

Assign all alerts from the `Microsoft.SQLServer.Windows.Monitoring` management pack to the _DBA Team_.

```xml
<assignment ID="9" Name="SQL" Owner="DBA Team" enabled="true">
  <ManagementPack Name="Microsoft.SQLServer.Core.Library" />
  <ManagementPack Name="Microsoft.SQLServer.Core.Views" />
  <ManagementPack Name="Microsoft.SQLServer.IS.Windows" />
  <ManagementPack Name="Microsoft.SQLServer.IS.Windows.Views" />
  <ManagementPack Name="Microsoft.SQLServer.Overrides" />
  <ManagementPack Name="Microsoft.SQLServer.Visualization.Library" />
  <ManagementPack Name="Microsoft.SQLServer.Windows.Discovery" />
  <ManagementPack Name="Microsoft.SQLServer.Windows.Mirroring" />
  <ManagementPack Name="Microsoft.SQLServer.Windows.Monitoring" />
  <ManagementPack Name="Microsoft.SQLServer.Windows.Monitoring.Override" />
  <ManagementPack Name="Microsoft.SQLServer.Windows.Views" />
</assignment>
```

##### Disabled Assignment

Do not assign all the alerts from the `Microsoft.Windows.Server.2016` management pack to the _Windows Team_.

```xml
<assignment ID="10" Name="Windows" Owner="Windows Team" enabled="false">
  <ManagementPack Name="Microsoft.Windows.Server.2016" />
</assignment>
```

### Exception

#### Exception Attributes

- **ID**: A numerical ID for the exception.
- **Owner**: The name of the owner to assign to the alert.
- **Name**: A logical group which is applied to the exceptions. This is used strictly for organizational purposes.
- **enabled**: Specifies if the exception is processed or not.

#### Exception Elements

- **Alert**: An element which describes an alert

##### Alert Exception

###### Alert Exception Attributes

- **Name**: The display name of the alert.

###### Alert Exception Elements

- **AlertProperty**: The property of the alert to filter on. Default is an empty string.
- **AlertPropertyMatches**: A string to compare against the specified property. Supports [regular expressions](https://docs.microsoft.com/powershell/module/microsoft.powershell.core/about/about_regular_expressions).

##### Management Pack Exception

###### Management Pack Exception Attributes

- **Name**: The name (not the display name) of the management pack.

#### Exception Examples

##### All Alerts

Assign all the _Health Service Heartbeat Failure_ alerts to the _Windows Team_.

```xml
<exception ID="1" Name="Server Offline" Owner="Windows Team" enabled="true">
  <Alert Name="Health Service Heartbeat Failure" />
</exception>
```

##### Specified Alerts

Assign the _Percentage Logical Disk Free Space is low_ to the _App Support_ team only when the monitoring object name matches `D:`, `E:`, or `F:`.

```xml
<exception ID="5" Name="ApplicationDrive" Owner="App Support" enabled="true">
  <Alert Name="Logical Disk Free Space is low">
    <AlertProperty>MonitoringObjectName</AlertProperty>
    <AlertPropertyMatches>[DEF]:</AlertPropertyMatches>
  </Alert>
</exception>
```
