# Assign Alerts

The **Assign SCOM Alerts** rule executes a powershell script on a timed schedule (default is 60 seconds) which assigns alerts to owners specified in the _assign.alert.config_ file.

## Config File

The _assign.alert.config_ file is comprised of Rules and Exceptions.

### Rule

Rules specify what owner should be assigned to all alerts in a management pack.

#### Rule Attributes

- **Name**: A logical group which is applied to the rules. This is used strictly for organizational purposes.
- **enabled**: Specifies if the rule is processed or not.

#### Rule Elements

- **managementPackName**: The name (not the display name) of the management pack.
- **Owner**: The name of the owner to assign to the alert.

#### Rule Examples

##### Enabled Rule

Assign all alerts from the `Microsoft.SQLServer.Windows.Monitoring` management pack to the _DBA Team_.

```xml
<Rule Name="SQLRule" enabled="true">
  <managementPackName>Microsoft.SQLServer.Windows.Monitoring</managementPackName>
  <Owner>DBA Team</Owner>
</Rule>
```

##### Disabled Rule

Do not assign all the alerts from the `Microsoft.Windows.Server.2016` management pack to the _Windows Team_.

```xml
<Rule Name="WindowsRule" enabled="false">
  <managementPackName>Microsoft.Windows.Server.2016</managementPackName>
  <Owner>Windows Team</Owner>
</Rule>
```

### Exception

#### Exception Attributes

- **Name**: A logical group which is applied to the exceptions. This is used strictly for organizational purposes.
- **enabled**: Specifies if the exception is processed or not.

#### Exception Elements

- **AlertName**: The display name of the alert.
- **Owner**: The name of the owner to assign to the alert.
- **AlertProperty**: The property of the alert to filter on. Default is an empty string.
- **AlertPropertyMatches**: A string to compare against the specified property. Supports [regular expressions](https://docs.microsoft.com/powershell/module/microsoft.powershell.core/about/about_regular_expressions).

#### Exception Examples

##### All Alerts

Assign all the _Health Service Heartbeat Failure_ alerts to the _Windows Team_.

```xml
<Exception Name="Health Service Exception" enabled="true">
  <AlertName>Health Service Heartbeat Failure</AlertName>
  <Owner>Windows Team</Owner>
  <AlertProperty/>
  <AlertPropertyMatches/>
</Exception>
```

##### Specified Alerts

Assign the _Percentage Logical Disk Free Space is low_ to the _App Support_ team only when the monitoring object name matches `D:`, `E:`, or `F:`.

```xml
<Exception Name="ApplicationDrive" enabled="true">
  <AlertName>Percentage Logical Disk Free Space is low</AlertName>
  <Owner>App Support</Owner>
  <AlertProperty>MonitoringObjectName</AlertProperty>
  <AlertPropertyMatches>[DEF]:</AlertPropertyMatches>
</Exception>
```
