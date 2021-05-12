[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [System.String]
    $AlertName,

    [Parameter(Mandatory = $true)]
    [System.String]
    $EventDetails,

    [Parameter()]
    [System.String]
    $DebugLogging = 'false'
)

# Gather the start time of the script
$startTime = Get-Date
$whoami = whoami

$debug = [System.Boolean]::Parse($DebugLogging)
$parameterString = $PSBoundParameters.GetEnumerator() | ForEach-Object -Process { "`n$($_.Key) => $($_.Value)" }

# Enable Write-Debug without inquiry when debug is enabled
if ($debug -or $DebugPreference -ne 'SilentlyContinue')
{
    $DebugPreference = 'Continue'
}

$scriptName = 'Invoke-ProcessStormEvent.ps1'
$scriptEventID = 9936

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

# Get the priority and severity
$alertDescription = @()
foreach ( $line in $EventDetails.Split("`n") )
{
    switch -Regex ( $line )
    {
        '^Priority: ([\d])'
        {
            $alertPriority = $Matches[1]
        }

        '^Severity: ([\d])'
        {
            $alertSeverity = $Matches[1]
        }
        
        default
        {
            $alertDescription += $_
        }
    }
}

# Build a hashtable with our values to make it easier to log and build the property bag
$result = @{
    AlertName = $AlertName
    AlertDescription = $alertDescription -join "`n"
    AlertPriority = $alertPriority
    AlertSeverity = $alertSeverity
}

if ( $debug )
{
	$i = 0
	$bagsString = $result | ForEach-Object -Process { $i++; $_.GetEnumerator() } | ForEach-Object -Process { "`n$($_.Key) => $($_.Value)" }
	$message = "`nProperty bag values: $bagsString"
	$momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
	Write-Debug -Message $message
}

# Create and fill the property bag
$bag = $momapi.CreatePropertyBag()
foreach ( $returnValue in $result.GetEnumerator() )
{
    $bag.AddValue($returnValue.Key,$returnValue.Value)
}

# Return the property bag
#$momapi.Return($bag)
$bag

# Log an event for script ending and total execution time.
$EndTime = Get-Date
$ScriptTime = ($EndTime - $StartTime).TotalSeconds

if ($debug)
{
    $message = "`n Script Completed. `n Script Runtime: ($ScriptTime) seconds.`n Executed as: $whoami."
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}
