[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [System.IO.FileInfo]
    $ConfigFile,

    [Parameter()]
    [System.String]
    $DebugLogging = 'false',

	[Parameter()]
	[System.String]
	$AssignedResolutionStateName = 'Assigned',

	[Parameter()]
	[System.String]
	$UnassignedResolutionStateName = 'Unassigned'
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

$scriptName = 'Alert-SCOMAlert.ps1'
$scriptEventID = 9931 # randomly generated for this script

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

function Format-xPathExpression
{
	param 
	(
		[Parameter(Mandatory = $true)]	
		[System.String]
		$Value
	)

    if ($Value.Contains("'"))
    {
	   return "\$Value\"
    }
    elseif ($Value.Contains('\'))
    {
	   return """$Value"""
    }
    else
    {
       return $Value;
    }
}

# Retrieve the configuration file with assignments and exceptions
$config = [System.Xml.XmlDocument] ( Get-Content -Path $ConfigFile.FullName -ErrorAction Stop )

# Get the resolution state number from SCOM
$assignedResolutionState = Get-SCOMAlertResolutionState -Name $AssignedResolutionStateName
$unassignedResolutionState = Get-SCOMAlertResolutionState -Name $UnassignedResolutionStateName

# Get all new alerts
$newAlerts = Get-SCOMAlert -ResolutionState 0

foreach ( $newAlert in $newAlerts )
{
	# Get the details of the alert
	$mpClass = Get-SCOMClass -Id $newAlert.MonitoringClassId
	$mpName = $mpClass.ManagementPackName
	$alertName = $newAlert.Name

	# Format the alert name for XPath
	$alertName = Format-xPathExpression -Value $alertName

	$searchStrings = @(
		"//Config/Exceptions/Exception[AlertName='$alertName' and @enabled='true']"
		"//Config/Exceptions/Exception[ManagementPackName='$mpName' and @enabled='true' and ( AlertProperty = 'MonitoringObjectFullName' or AlertProperty = 'MonitoringObjectPath' or AlertProperty = 'MonitoringObjectDisplayName' )]"
		"//Config/Rules/Rule[managementPackName='$mpName' and @enabled='true']"
	)

	foreach ( $searchString in $searchStrings )
	{
		$assignmentRule = $config.SelectSingleNode($searchString)

		if ( -not [System.String]::IsNullOrEmpty($assignmentRule.AlertProperty) )
		{
			if ( $newAlert.($assignmentRule.AlertProperty) -notlike "*$($newAlert.($assignmentRule.AlertProperty))*" )
			{
				$assignmentRule = $null
			}
		}

		if ( $assignmentRule )
		{
			$assignedTo = $assignmentRule.Owner
			break
		}
	}

	if ( $assignmentRule )
	{
		$assignedTo = $assignmentRule.Owner
	}
	else
	{
		$assignedTo = $UnassignedResolutionStateName
	}

	#region Set Alert
	$setScomAlertParams = @{
		Owner = $assignedTo
		Comment = ( 'Alert automation assigned to: {0}' -f $assignedTo )
	}

	if ( $assignedTo -ne $UnassignedResolutionStateName )
	{
		$newAlert | Set-SCOMAlert @setScomAlertParams -ResolutionState $assignedResolutionState
	}
	else
	{
		$newAlert | Set-SCOMAlert @setScomAlertParams -ResolutionState $unassignedResolutionState
	}
	#endregion
}

# Log an event for script ending and total execution time.
$endTime = Get-Date
$scriptTime = ($EndTime - $StartTime).TotalSeconds

if ($debug)
{
    $message = "`n Script Completed. `n Script Runtime: ($scriptTime) seconds."
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}
