[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [System.IO.FileInfo]
    $ConfigFile,

    [Parameter()]
    [System.String]
    $DebugLogging = 'false'
)

# Gather the start time of the script
$startTime = Get-Date

$debug = [System.Boolean]::Parse($DebugLogging)
$parameterString = $PSBoundParameters.GetEnumerator() | ForEach-Object -Process { "`n$($_.Key) => $($_.Value)" }

# Enable Write-Debug without inquiry when debug is enabled
if ($debug -or $DebugPreference -ne 'SilentlyContinue')
{
    $DebugPreference = 'Continue'
}

$scriptName = 'Escalate-SCOMAlert.ps1'
$scriptEventID = 15813 # randomly generated for this script

# Load MOMScript API
$momapi = New-Object -comObject MOM.ScriptAPI

trap
{
    $message = "`n $parameterString `n $($_.ToString())"
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 1, $message)
    break
}

# Log script event that we are starting task
if ($debug)
{
    $message = "`nScript is starting. $parameterString"
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}

#region Functions
function Format-DateField
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Criteria,
        
        [Parameter(Mandatory = $true)]
        [System.Int32]
        $TimeOffset
    )

    # COMPUTE TIME OFFSET; CAST AS STRING VALUE
    $m_timeOffset = [System.Int32] - $TimeOffset
    $compareDate = [System.DateTime] (Get-Date).AddMinutes($m_timeOffset).ToUniversalTime()
    $dateString = $compareDate.ToString("MM/dd/yyyy HH:mm:ss")

    switch -regex ( $Criteria )
    {
        '__LastModified__' { $formattedCriteria = $Criteria.Replace( '__LastModified__', $dateString ) }
        '__TimeRaised__' { $formattedCriteria = $Criteria.Replace( '__TimeRaised__', $dateString ) }
        default { $formattedCriteria = $Criteria }
    }

    # REPLACE ESCAPED XML CHARACTERS
    $formattedCriteria = $formattedCriteria.Replace("&lt;", "<")
    $formattedCriteria = $formattedCriteria.Replace("&gt;", ">")

    return $formattedCriteria
}

function CleanPostPipelineFilter
{
    param ([string]$postPipelineFilter)
    [string]$tmpString = ""

    # REPLACE ESCAPED XML CHARACTERS
    $tmpString = $postPipelineFilter.Replace("&lt;", "<")
    $tmpString = $postPipelineFilter.Replace("&gt;", ">")

    Return $tmpString
}
#endregion Functions

# RETRIEVE CONFIGURATION FILE WITH RULES AND EXCEPTIONS
$config = [System.Xml.XmlDocument] ( Get-Content -Path $ConfigFile.FullName )

# LOG FILE
<#
$logFilePath = $config.config.settings.outputpath.name
$fileName = "AlertEscalation." + (Get-Date -Format "yyyy.MM.dd") + ".log"
$logFileName = Join-Path -Path $logFilePath $fileName
#>

if ( -not ( Get-Module -Name OperationsManager ) )
{
    Import-Module OperationsManager
}

#region Update Type Data

# Add a UnitMonitor property to the alert which contains the associated unit monitor object
$updateTypeDataUnitMonitorParameters = @{
    TypeName   = 'Microsoft.EnterpriseManagement.Monitoring.MonitoringAlert'
    MemberType = 'ScriptProperty'
    MemberName = 'UnitMonitor'
    Value      = {
        if ( $this.IsMonitorAlert )
        {
            function GetScomChildNodes
            {
                [CmdletBinding()]
                param
                (
                    [Parameter(Mandatory = $true)]
                    [System.Object]
                    $MonitoringHierarchyNode
                )

                # Create an array for the unit monitors
                $unitMonitors = @()

                foreach ( $childNode in $MonitoringHierarchyNode.ChildNodes )
                {
                    if ( $childNode.Item.GetType().FullName -eq 'Microsoft.EnterpriseManagement.Configuration.UnitMonitor' )
                    {
                        Write-Verbose -Message "Unit Monitor: $($childNode.Item.DisplayName)"
                        $unitMonitors += $childNode.Item
                    }
                    else
                    {
                        Write-Verbose -Message $childNode.Item.DisplayName
                        Write-Verbose -Message ($childNode.GetType().FullName)
                        GetScomChildNodes -MonitoringHierarchyNode $childNode.Item
                    }
                }

                return $unitMonitors
            }

            # Get the associated monitor from the alert
            if ( $this.IsMonitorAlert )
            {
                $monitor = Get-SCOMClassInstance -Id $this.MonitoringObjectId
            }
            else
            {
                Write-Verbose -Message ( 'The alert "{0}" is not a monitor alert.' -f $this.Name )
                exit
            }
    
            # Get the child nodes of the monitor
            $unitMonitors = @()
            foreach ( $childNode in $monitor.GetMonitorHierarchy().ChildNodes )
            {
                $unitMonitors += GetScomChildNodes -MonitoringHierarchyNode $childNode
            }

            # Get the unit monitor which generated the alert
            $unitMonitor = $unitMonitors | Where-Object -FilterScript { $_.Id -eq $this.MonitoringRuleId }

            return $unitMonitor
        }
    }
}

if ( -not ( Get-TypeData -TypeName $updateTypeDataUnitMonitorParameters.TypeName ).Members[$updateTypeDataUnitMonitorParameters.MemberName] )
{
    Update-TypeData @updateTypeDataUnitMonitorParameters
}

# Add a Monitor property to the alert which contains the associated unit monitor object
$updateTypeDataMonitorParameters = @{
    TypeName   = 'Microsoft.EnterpriseManagement.Monitoring.MonitoringAlert'
    MemberType = 'ScriptProperty'
    MemberName = 'Monitor'
    Value      = {
        Get-SCOMClassInstance -Id $this.MonitoringObjectId
    }
}

if ( -not ( Get-TypeData -TypeName $updateTypeDataMonitorParameters.TypeName ).Members[$updateTypeDataMonitorParameters.MemberName] )
{
    Update-TypeData @updateTypeDataMonitorParameters
}

# Add a HealthStateSuccess property to the alert which contains the associated unit monitor object
$updateTypeDataHealthStateSuccessParameters = @{
    TypeName   = 'Microsoft.EnterpriseManagement.Monitoring.MonitoringAlert'
    MemberType = 'ScriptProperty'
    MemberName = 'HealthStateSuccess'
    Value      = {
        return $this.UnitMonitor.OperationalStateCollection |
        Where-Object -FilterScript { $_.HealthState -eq 'Success' } |
        Select-Object -ExpandProperty Name
    }
}

if ( -not ( Get-TypeData -TypeName $updateTypeDataHealthStateSuccessParameters.TypeName ).Members[$updateTypeDataHealthStateSuccessParameters.MemberName] )
{
    Update-TypeData @updateTypeDataHealthStateSuccessParameters
}

#endregion Update Type Data

# INITIALIZE AlertCount
$alertCount = 0

# Alert Storm Processing
$alertStormRules = $config.SelectNodes("//config/alertStormRules/stormRule[@enabled='true']") | Sort-Object { $_.Sequence }

foreach ( $alertStormRule in $alertStormRules )
{
    # Get the alerts defined by the criteria and group them by the defined property
    $potentialStormAlertGroups = Get-SCOMAlert -Criteria $alertStormRule.Criteria.InnerText | Group-Object -Property $alertStormRule.Property | Where-Object -FilterScript { $_.Count -gt 1 }

    # Define a counter which will be used to further subdivide the alerts into groups
    $groupCounter = 0

    # Create a hashtable to store the new groups of alerts
    $stormAlertGroups = @{ $groupCounter = @() }

    foreach ( $potentialStormAlertGroup in $potentialStormAlertGroups )
    {
        # Create a variable to base the time elapsed calcluations off of
        $previousDateTime = [System.DateTime]::MinValue
        
        foreach ( $alert in ( $potentialStormAlertGroup.Group | Sort-Object -Property TimeRaised ) )
        {
            # If the alert was raised less than the defined window from the previous alert
            if ( ( $alert.TimeRaised - $previousDateTime ).TotalMinutes -lt $alertStormRule.Window )
            {
                # Add the alert to the current group
                $stormAlertGroups[$groupCounter] += $alert
            }
            else
            {
                # Increment the group counter
                $groupCounter++

                # Create a new group
                $stormAlertGroups[$groupCounter] = @($alert)
            }

            # Update the Previous Date/Time variable
            $previousDateTime = $alert.TimeRaised
        }
    }
    
    # Get the groups which meet the threshold for number of the same alert
    $stormAlerts = $stormAlertGroups.GetEnumerator() | Where-Object -FilterScript { $_.Value.Count -ge $alertStormRule.Count }

    foreach ( $stormAlert in $stormAlerts )
    {
        # Get the alerts which were previously tagged as an alert storm
        $oldAlertStormAlerts = $stormAlert.Value | Where-Object -FilterScript { ( $_.ResolutionState -eq 18 ) -and $_.TicketID }
        
        if ( $oldAlertStormAlerts.Count -gt 0 )
        {
            # Get the existing "ticket id"
            $ticketId = $oldAlertStormAlerts | Select-Object -ExpandProperty TicketId -Unique
        }
        else
        {
            # Get the alert name
            $alertName = $stormAlert.Value | Select-Object -ExpandProperty Name -Unique

            # Define the "ticket id"
            $ticketId = ( Get-Date -Format 'MM/dd/yyyy hh:mm:ss {0}' ) -f $alertName
            
            # Get a unique list of monitoring objects
            $monitoringObjects = $stormAlert.Value | Select-Object -ExpandProperty MonitoringObjectFullName -Unique | Sort-Object
        
            # Define the string which will be passed in as the "script name" property for LogScriptEvent
            $stormDescription = "The alert ""$alertName"" was triggered $($stormAlert.Value.Count) times for the following objects:"
        
            # Define the event details
            $eventDetails = New-Object -TypeName System.Text.StringBuilder
            $eventDetails.AppendLine() > $null
            $eventDetails.AppendLine() > $null
            $monitoringObjects | ForEach-Object -Process { $eventDetails.AppendLine($_) > $null }
            $eventDetails.AppendLine() > $null
            $eventDetails.AppendLine("Internal ticket id: $ticketId") > $null

            # Get the highest severity of the selected alerts
            $highestAlertSeverity = $stormAlert.Value.Severity | Sort-Object -Property value__ -Descending | Select-Object -First 1 -Unique

            # Get the highest priority of the selected alerts
            $highestAlertPriority = $stormAlert.Value.Priority | Sort-Object -Property value__ -Descending | Select-Object -First 1 -Unique

            # Determine what the event severity should be
            if (
                $highestAlertSeverity -eq 'Error' -and
                $highestAlertPriority -eq 'High'
            )
            {
                # Error
                $eventSeverity = 1
            }
            elseif (
                $highestAlertSeverity -in @('Error', 'Warning') -and
                $highestAlertPriority -in @('Normal', 'Low')
            )
            {
                # Warning
                $eventSeverity = 2
            }
            else
            {
                # Information
                $eventSeverity = 0
            }

            # Raise an event indicating an alert storm was detected
            $momApi.LogScriptEvent($stormDescription, 9908, $eventSeverity, $eventDetails.ToString())

        }
        
        # Mark the alert as being part of an alert storm
        $stormAlert.Value | Where-Object -FilterScript { $_.ResolutionState -ne 18 } | Set-SCOMAlert -ResolutionState 18 -Comment $alertStormRule.Comment.InnerText -TicketId $ticketId
    }
}

# PROCESS EXCEPTIONS FIRST
$alertExceptions = $config.SelectNodes("//config/exceptions/exception[@enabled='true']") | Sort-Object { $_.Sequence }

foreach ($exception in $alertExceptions)
{
    # ASSIGN VALUES
    # Write-Host $exception.name
    [string]$criteria = $exception.Criteria.InnerText
    [int]$newResolutionState = $exception.NewResolutionState
    [string]$postPipelineFilter = $exception.PostPipelineFilter #.InnerText
    [string]$comment = $exception.Comment.InnerText
    [string]$name = $exception.Name

    # REPLACE TIME BASED CRITERIA
    if ($criteria -match "__TimeRaised__")
    {
        [int]$timeRaisedAge = $exception.TimeRaisedAge
        $criteria = Format-DateField $criteria $timeRaisedAge
    }
    if ($criteria -match "__LastModified__")
    {
        [int]$lastModifiedAge = $exception.LastModifiedAge
        $criteria = Format-DateField $criteria $lastModifiedAge
    }

    # COLLECT ALERTS BASED ON CRITERIA
    If ($postPipelineFilter -eq "")
    {
        $alerts = Get-SCOMAlert -Criteria $criteria 
    } 
    Else 
    {
        [string]$cleanString = CleanPostPipelineFilter $postPipelineFilter
        [scriptblock]$filter = [System.Management.Automation.ScriptBlock]::Create($cleanString)

        $alerts = Get-SCOMAlert -Criteria $criteria | Where-Object -FilterScript $filter
    }

    ### UPDATE MATCHING ALERTS TO NEW RESOLUTION STATE
    If ($alerts.Count -gt 0)
    {
        $alerts | Set-SCOMAlert -ResolutionState $newResolutionState -Comment $Comment
        $AlertCount = $alerts.Count
        Write-Verbose -Message $criteria        

        if ($debug)
        {
            $message = "`nUpdated $AlertCount alert(s) to resolution state $newResolutionState (Exception: $name)."
            $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
            Write-Debug -Message $message
        }
    }
    

    # RESET EXCEPTION VALUES
    $criteria = $null
    $newResolutionState = $null
    $postPipelineFilter = $null
    $comment = $null
    $name = $null

}

# PROCESS RULES SECOND
$alertRules = $config.SelectNodes("//config/rules/rule[@enabled='true']") | Sort-Object { $_.sequence }

foreach ($rule in $alertRules)
{
    # ASSIGN VALUES
    Write-Verbose -Message $rule.name
    $criteria = $rule.Criteria.InnerText
    $newResolutionState = [System.Int32] $rule.NewResolutionState
    $postPipelineFilter = $rule.PostPipelineFilter #.InnerText
    $comment = $rule.Comment.InnerText
    $name = $rule.name

    # REPLACE TIME BASED CRITERIA
    if ($criteria -match '__TimeRaised__')
    {
        $timeRaisedAge = [System.Int32] $rule.TimeRaisedAge
        $criteria = Format-DateField $criteria $timeRaisedAge
    }
    if ($criteria -match '__LastModified__')
    {
        $lastModifiedAge = [System.Int32] $rule.LastModifiedAge
        $criteria = Format-DateField $criteria $lastModifiedAge
    }

    # COLLECT ALERTS BASED ON CRITERIA
    if ( [System.String]::IsNullOrEmpty($postPipelineFilter) )
    {
        $alerts = Get-SCOMAlert -Criteria $criteria 
    } 
    else
    {
        $cleanString = CleanPostPipelineFilter $postPipelineFilter
        $filter = [System.Management.Automation.ScriptBlock]::Create($cleanString)
        $alerts = Get-SCOMAlert -Criteria $criteria | Where-Object -FilterScript $filter
    }

    ### UPDATE MATCHING ALERTS TO NEW RESOLUTION STATE
    If ($alerts.Count -gt 0)
    {
        $alerts | Set-SCOMAlert -ResolutionState $newResolutionState -Comment $Comment
        Write-Verbose -Message $criteria
        $AlertCount = $alerts.Count

        if ($debug)
        {
            $message = "`nUpdated $AlertCount alert(s) to resolution state $newResolutionState (Rule: $name)."
            $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
            Write-Debug -Message $message
        }
    }

    # RESET RULE VALUES
    Remove-Variable -Name criteria,newResolutionState,postPipelineFilter,comment,name -ErrorAction Continue
}

# Log an event for script ending and total execution time.
$EndTime = Get-Date
$ScriptTime = ($EndTime - $StartTime).TotalSeconds

if ($debug)
{
    $message = "`n Script Completed. `n Script Runtime: ($ScriptTime) seconds."
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}
