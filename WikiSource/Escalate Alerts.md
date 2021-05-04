# Escalate Alerts

The **Escalate SCOM Alerts** rule executes a powershell script on a timed schedule (default is 5 minutes) which updates the resolution state on alerts based on the _escalate.alert.config_ file.

## Config File

The _escalate.alert.config_ file is comprised of **alertStormRules**, **rules**, and **exceptions**.

### Alert Storm Rule

The alert storm rules define what constitutes an alert storm.

#### Alert Storm Rule Attributes

- **name**: A logical group which is applied to the rules. This is used strictly for organizational purposes.
- **enabled**: Specifies if the rule is processed or not.

#### Alert Storm Rule Elements

- **Sequence**: The order in which the rule should be processed.
- **Property**: The property on which to filter the alerts.
- **Criteria**: The criteria for the [`Get-SCOMAlert` cmdlet](https://docs.microsoft.com/powershell/module/operationsmanager/get-scomalert?#parameters).
- **Count**: The threshold (in minutes) for the number of alerts which is considered a storm.
- **Window**: The period (in minutes) over which to group alerts.
- **NewResolutionState**: The ID of the new resolution state which identifies the alert as being part of a storm.
- **Comment**: A string which is added to the alert when the alert is updated about the change which was made.
- **SendNotification**: Y/N value for if a notification is emailed to an address.
- **NotificationRecipients**: The email address which receives the notification.

#### Alert Storm Rule Examples

##### Alert Name

Declare an alert storm when 10 or more alerts with the same name are generated over a 5 minute period.

```xml
<stormRule name="Alert Count by Name" enabled="true">
  <Sequence>100</Sequence>
  <Property>Name</Property>
  <Criteria><![CDATA[ResolutionState<>255]]></Criteria>
  <Count>10</Count>
  <Window>5</Window>
  <NewResolutionState>18</NewResolutionState>
  <Comment><![CDATA[Alert updated by the alert automation: Alert Storm]]></Comment>
  <SendNotification>N</SendNotification>
  <NotificationRecipients>dan.reist@microsoft.com</NotificationRecipients>
</stormRule>
```

##### Monitoring Object

Declare an alert storm when 10 or more alerts with the same monitoring object ID are generated over a 5 minute period.

```xml
<stormRule name="Alert count by MonitoringObjectId" enabled="true">
  <Sequence>101</Sequence>
  <Property>MonitoringObjectId</Property>
  <Criteria><![CDATA[ResolutionState<>255]]></Criteria>
  <Count>10</Count>
  <Window>5</Window>
  <NewResolutionState>18</NewResolutionState>
  <Comment><![CDATA[Alert updated by the alert automation: Alert Storm]]></Comment>
  <SendNotification>N</SendNotification>
  <NotificationRecipients>dan.reist@microsoft.com</NotificationRecipients>
</stormRule>
```

### Rules

#### Rule Attributes

- **name**: A logical group which is applied to the rules. This is used strictly for organizational purposes.
- **enabled**: Specifies if the rule is processed or not.

#### Rule Elements

- **Category**: ???? What does this do ????
- **Description**: Describe what the rule does.
- **Sequence**: The order in which the rule should be processed.
- **Criteria**: The criteria for the [`Get-SCOMAlert` cmdlet](https://docs.microsoft.com/powershell/module/operationsmanager/get-scomalert?#parameters).
- **NewResolutionState**: The ID of the new resolution state.
- **LastModifiedAge**: The amount of time (in minutes) the alert was in the current resolution state.
- **PostPipelineFilter**: A filter to apply in the PowerShell pipeline to further select the alerts.
- **Comment**: A string which is added to the alert when the alert is updated about the change which was made.

#### Rule Examples

##### Close Resolved Alerts

Close alerts that have been sitting in the _Resolved_ state for more than 24 hours.

```xml
<rule name="Close Resolved Alerts: Closed" enabled="true">
  <Category></Category>
  <Description><![CDATA[Close alerts that have been sitting in 'Resolved' state for more than 24 hours]]><Description>
  <Sequence>1</Sequence>
  <Criteria><![CDATA[ResolutionState=254 AND LastModified < '__LastModified__']]></Criteria>
  <NewResolutionState>255</NewResolutionState>
  <LastModifiedAge>1440</LastModifiedAge> 
  <PostPipelineFilter></PostPipelineFilter>
  <Comment><![CDATA[Alert updated by the alert automation: Closed]]></Comment>
</rule>
```

##### Verified Alert

Move alerts to _Verified_ when the repeat count is incremented multiple times within a 10 minute period.

```xml
<rule name="Update Awaiting Evidence: Verified" enabled="true"> 
  <Category></Category>
  <Description><![CDATA[Update alerts from Awaiting Evidence to Verified]]></Description>
  <Sequence>6</Sequence>
  <Criteria><![CDATA[ResolutionState=247 AND LastModified < '__LastModified__' AND IsMonitorAlert=0]]></Criteria>
  <NewResolutionState>15</NewResolutionState>
  <LastModifiedAge>10</LastModifiedAge>
  <PostPipelineFilter>$_.RepeatCount -gt 0</PostPipelineFilter>
  <Comment><![CDATA[Alert updated by the alert automation: Verified]]></Comment>
</rule>
```

### Exceptions

#### Exceptions Attributes

- **name**: A logical group which is applied to the rules. This is used strictly for organizational purposes.
- **enabled**: Specifies if the rule is processed or not.

#### Exceptions Elements

- **Category**: ???? What does this do ????
- **Description**: Describe what the rule does.
- **Sequence**: The order in which the rule should be processed.
- **Criteria**: The criteria for the [`Get-SCOMAlert` cmdlet](https://docs.microsoft.com/powershell/module/operationsmanager/get-scomalert?#parameters).
- **NewResolutionState**: The ID of the new resolution state.
- **TimeRaisedAge**: The amount of time (in minutes) since the alert was raised.
- **PostPipelineFilter**: A filter to apply in the PowerShell pipeline to further select the alerts.
- **Comment**: A string which is added to the alert when the alert is updated about the change which was made.

#### Exceptions Examples

##### Close Noisy Alert

Close _Power Shell Script failed to run_ alerts if the repeat count is less than 10 and the alert is less than 10  minutes old.

```xml
<exception name="Power Shell Script failed to run" enabled="true">
  <Category>SCOM</Category>
  <Sequence>20</Sequence>
  <Criteria><![CDATA[ResolutionState=247 AND Name='Power Shell Script failed to run' AND TimeRaised < '__TimeRaised__']]></Criteria>
  <NewResolutionState>255</NewResolutionState>
  <TimeRaisedAge>10</TimeRaisedAge>
  <PostPipelineFilter>$_.RepeatCount -lt 10</PostPipelineFilter>
  <Comment><![CDATA[Alert updated by the alert automation: Closed]]></Comment>
  <CheckHealth>true</CheckHealth>
        </exception>
```
