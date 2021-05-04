[CmdletBinding()]
param
(
    [Parameter()]
    [System.String]
    $DebugLogging = 'false'
)

# Gather the start time of the script
$startTime = Get-Date

$debug = [System.Boolean]::Parse($DebugLogging)
$parameterString = $PSBoundParameters.GetEnumerator() | ForEach-Object -Process { "`n$($_.Key) => $($_.Value)" }

# Enable Write-Debug without inquiry when debug is enabled
if ( $debug -or $DebugPreference -ne 'SilentlyContinue' )
{
    $DebugPreference = 'Continue'
}

$scriptName = 'Add-ResolutionStates.ps1'
$scriptEventID = 9934

# Load MOMScript API
$momapi = New-Object -comObject MOM.ScriptAPI

trap
{
    $message = "`n $parameterString `n $($_.ToString())"
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 1, $message)
    break
}

# Log script event that we are starting task
if ( $debug )
{
    $message = "`nScript is starting. $parameterString"
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}

$states = @{
	5 = 'Assigned'
	15 = 'Verified'
	18 = 'Alert Storm'
}

foreach ( $state in $states.GetEnumerator() )
{
	$addScomAlertResolutionStateParams = @{
        Name = $state.Value
        ResolutionStateCode = $state.Key
    }

    # Determine if the resolution state exists
    $alertResolutionState = Get-SCOMAlertResolutionState -Name $addScomAlertResolutionStateParams.Name

    if ( -not $alertResolutionState )
    {
        if ( $debug )
        {
            $addScomAlertResolutionStateParamsString = ( $addScomAlertResolutionStateParams.GetEnumerator() | ForEach-Object -Process { "`n$($_.Key) => $($_.Value)" } ) -join ''
            $message = "Add-SCOMAlertResolutionState $addScomAlertResolutionStateParamsString"
            $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
            Write-Debug -Message $message
        }
        $alertResolutionState = Add-SCOMAlertResolutionState @addScomAlertResolutionStateParams
    }
}

# Log an event for script ending and total execution time.
$endTime = Get-Date
$scriptTime = ( $endTime - $startTime ).TotalSeconds

if ( $debug )
{
    $message = "`nScript Completed. `nScript Runtime: ($scriptTime) seconds."
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}
