[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [System.String]
    $ConfigFile,

    [Parameter()]
    [System.String]
    $AssignedResolutionStateName = 'Assigned',

    [Parameter()]
    [System.String]
    $UnassignedResolutionStateName = 'Assigned',

    [Parameter()]
    [System.String]
    $DefaultOwner = 'Unassigned',

    [Parameter()]
    [System.String]
    $DebugLogging = 'false'
)

# Gather the start time of the script
$startTime = Get-Date
$whoami = "$($env:USERDNSDOMAIN)\$($env:USERNAME)"

$debug = [System.Boolean]::Parse($DebugLogging)
$parameterString = $PSBoundParameters.GetEnumerator() | ForEach-Object -Process { "`n$($_.Key) => $($_.Value)" }

# Enable Write-Debug without inquiry when debug is enabled
if ($debug -or $DebugPreference -ne 'SilentlyContinue')
{
    $DebugPreference = 'Continue'
}

$scriptName = 'Assign-ScomAlert.ps1'
$scriptEventID = 9931

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
    $message = "`nScript is starting. `nExecuted as: $whoami. $parameterString"
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}

function Format-xPathExpression
{
    param 
    (
        [Parameter(Mandatory = $true)]    
        [System.String]
        $Value
    )

    $charactersToReplace = @{
        "'" = '&quot;'
        '\' = '\\'
    }

    foreach ( $characterToReplace in $charactersToReplace.GetEnumerator() )
    {
        $Value = $Value.Replace($characterToReplace.Key, $characterToReplace.Value)
    }

    return $Value
}

# Get the config file object to ensure it exists
$configurationFile = Get-Item -Path $ConfigFile -ErrorAction Stop

# Get the config file schema
$configurationFileSchema = Get-Item -Path '$FileResource[Name="SCOM.Alert.Management.AssignAlertConfigSchema"]/Path$' -ErrorAction Stop

# Retrieve the configuration file with assignments and exceptions
$config = [System.Xml.XmlDocument] ( Get-Content -Path $configurationFile.FullName -ErrorAction Stop )

# Validate the schema
$config.Schemas.Add('',$configurationFileSchema.FullName) > $null
$config.Validate($null)

# Get the resolution state number from SCOM
$assignedResolutionState = Get-SCOMAlertResolutionState -Name $AssignedResolutionStateName | Select-Object -ExpandProperty ResolutionState
$unassignedResolutionState = Get-SCOMAlertResolutionState -Name $UnassignedResolutionStateName | Select-Object -ExpandProperty ResolutionState
if ($debug)
{
    $message = "`nAssigned Resolution State: $assignedResolutionState `nUnassigned Resolution State: $unassignedResolutionState"
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}

# Get all new alerts
$newAlerts = Get-SCOMAlert -Criteria "ResolutionState <> 255 AND ( Owner IS NULL OR Owner = '' OR Owner = '$DefaultOwner')"
if ( $debug )
{
    $message = "$($newAlerts.Count) alert(s) found to process."
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}

foreach ( $newAlert in $newAlerts )
{
    # Get the management pack the alert was generated from
    if ( $newAlert.IsMonitorAlert )
    {
        $monitor = $newAlert.MonitoringRuleId | Get-SCOMMonitor
        $mpName = $monitor.GetManagementPack().Name
    }
    else
    {
        $mpName = $newAlert.MonitoringRuleId | Get-SCOMRule | Select-Object -ExpandProperty ManagementPackName
    }

    # Get the alert name
    $alertName = $newAlert.Name

    # Format the alert name for XPath
    $alertName = Format-xPathExpression -Value $alertName

    #region Determine Alert Owner
    # Order of operation
    # 1. Exception: Find by Alert Name with Alert Property
    # 2. Exception: Find by Alert Name (without Property)
    # 3. Exception: Find by Management Pack with Alert property
    # 4. Assignment: Find by Management Pack
    $searchStrings = @(
        "//config/exceptions/exception[@enabled='true']/Alert[@Name='$alertName']/AlertProperty/ancestor::exception"
        "//config/exceptions/exception[@enabled='true']/Alert[@Name='$alertName'][count(AlertProperty) = 0]/parent::exception"
        "//config/exceptions/exception[@enabled='true']/ManagementPack[@Name='$mpName']/AlertProperty/ancestor::exception"
        "//config/assignments/assignment[@enabled='true']/ManagementPack[@Name='$mpName']/parent::assignment"
    )

    foreach ( $searchString in $searchStrings )
    {
        $assignmentRule = $config.SelectSingleNode($searchString) |
            Where-Object -FilterScript {
                $assignmentRule = $_

                if ( $assignmentRule | Get-Member -Name Alert )
                {
                    $newAlert.($assignmentRule.Alert.AlertProperty) -match "$($assignmentRule.Alert.AlertPropertyMatches)"
                }
                elseif ( $assignmentRule | Get-Member -Name AlertProperty )
                {
                    $newAlert.($assignmentRule.AlertProperty) -match "$($assignmentRule.AlertPropertyMatches)"
                }
            }

        if ( $assignmentRule )
        {
            $ruleID = $assignmentRule.ID
            $ruleName = $assignmentRule.Name
            if($searchString -match 'exception')
            {
                $assignmentType = 'Exception'
            }
            else
            {
                $assignmentType = 'Assignment'
            }
            $assignedTo = $assignmentRule.Owner

            if ( $debug )
            {
                $message = "Alert auto assigned to: $assignedTo. Type: $assignmentType; ID: $ruleID; Name: $ruleName."
                $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
                Write-Debug -Message $message
            }
            break
        }
    }

    if ( -not $assignedTo )
    {
        $assignedTo = $DefaultOwner
        $ruleID = ''
        $ruleName = 'None'
        $assignmentType = 'Default'
        $message = "`nNo assignment rule found for an alert.`nManagement Pack: $mpName`nAlert: $alertName"
        $momapi.LogScriptEvent($scriptName, $scriptEventID, 2, $message)
        Write-Warning -Message $message
    }
    #endregion Determine Alert Owner

    #region Assign Alert
    $setScomAlertParams = @{
        Alert = $newAlert
        Owner = $assignedTo
        ResolutionState = $assignedResolutionState
        Comment = "Alert auto assigned to: $assignedTo. Type: $assignmentType; ID: $ruleID; Name: $ruleName."
    }

    # If the alert is assigned to the "default" owner, set the resolution state to the "Unassigned" value
    if ( $assignedTo -eq $DefaultOwner )
    {
        $setScomAlertParams.ResolutionState = $unassignedResolutionState
    }

    # Only set the owner if it is different
    if ( $newAlert.Owner -ne $setScomAlertParams.Owner )
    {
        if ( $debug )
        {
            $setScomAlertParamsString = ( $setScomAlertParams.GetEnumerator() | ForEach-Object -Process { " -$($_.Key) '$($_.Value)'" } ) -join ''
            $message = "Set the alert owner `nSet-SCOMAlert $setScomAlertParamsString"
            $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
        }
        Set-SCOMAlert @setScomAlertParams
    }
    #endregion Assign Alert
}

# Log an event for script ending and total execution time.
$endTime = Get-Date
$scriptTime = ($EndTime - $StartTime).TotalSeconds

if ( $debug )
{
    $message = "`n Script Completed. `n Script Runtime: ($scriptTime) seconds.`n Executed as: $whoami."
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}
