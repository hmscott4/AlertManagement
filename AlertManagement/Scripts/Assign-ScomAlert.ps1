[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [System.IO.FileInfo]
    $ConfigFile,

	[Parameter()]
	[System.String]
	$AssignedResolutionStateName = 'Assigned',

	[Parameter()]
	[System.String]
	$UnassignedResolutionStateName = 'Unassigned',

	[Parameter()]
	[System.String]
	$DefaultOwner = 'Unassigned',

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

$scriptName = 'Alert-SCOMAlert.ps1'
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

	#region Determine Alert Owner
	$searchStrings = @(
		"//Config/Exceptions/Exception[AlertName='$alertName' and @enabled='true']"
		"//Config/Rules/Rule[managementPackName='$mpName' and @enabled='true']"
	)

	foreach ( $searchString in $searchStrings )
	{
		$assignmentRule = $config.SelectSingleNode($searchString) |
		Where-Object -FilterScript { $newAlert.($_.AlertProperty) -match "*$($newAlert.($_.AlertProperty))*" }

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
		$assignedTo = $DefaultOwner
		$message = "No assignment rule found for an alert.`nManagement Pack: $mpName`nAlert: $alertName"
		$momapi.LogScriptEvent($scriptName, $scriptEventID, 2, $message)
		Write-Verbose -Message $message
	}
	#endregion Determine Alert Owner

	#region Assign Alert
	$setScomAlertParams = @{
		Alert = $newAlert
		Owner = $assignedTo
		ResolutionState = $null
		Comment = "Alert automation assigned to: $assignedTo"
	}

	if ( $assignedTo -ne $DefaultOwner )
	{
		$setScomAlertParams.ResolutionState = $assignedResolutionState
	}
	else
	{
		$setScomAlertParams.ResolutionState = $unassignedResolutionState
	}

	if ( $debug )
	{
		$setScomAlertParamsString = ( $setScomAlertParams.GetEnumerator() | ForEach-Object -Process { " -$($_.Key) '$($_.Value)'" } ) -join ''
		$message = "Set the alert owner `nSet-SCOMAlert $setScomAlertParamsString"
		$momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
	}
	Set-SCOMAlert @setScomAlertParams
	#endregion Assign Alert
}

# Log an event for script ending and total execution time.
$endTime = Get-Date
$scriptTime = ($EndTime - $StartTime).TotalSeconds

if ( $debug )
{
    $message = "`n Script Completed. `n Script Runtime: ($scriptTime) seconds."
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}