[CmdletBinding()]
param
(
    [Parameter(Mandatory = $true)]
    [System.IO.DirectoryInfo]
    $Destination,

    [Parameter()]
    [System.String]
    $Force = 'false',

    [Parameter()]
    [System.String]
    $DebugLogging = 'false'
)

# Gather the start time of the script
$startTime = Get-Date

$debug = [System.Boolean]::Parse($DebugLogging)
$forceCopy = [System.Boolean]::Parse($Force)
$parameterString = $PSBoundParameters.GetEnumerator() | ForEach-Object -Process { "`n$($_.Key) => $($_.Value)" }

# Enable Write-Debug without inquiry when debug is enabled
if ( $debug -or $DebugPreference -ne 'SilentlyContinue' )
{
    $DebugPreference = 'Continue'
}

$scriptName = 'Copy-ConfigurationFiles.ps1'
$scriptEventID = 9935

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

# Define an array with the config files from the management pack
$configFilePaths = @(
    '$FileResource[Name="SCOM.Alert.Management.AssignAlertConfig"]/Path$'
    '$FileResource[Name="SCOM.Alert.Management.EscalateAlertConfig"]/Path$'
)
if ( $debug )
{
    $message = "`nConfiguration Files: `n$($configFilePaths -join "`n")"
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}

# Get the configuration files
$configFiles = Get-Item -Path $configFilePaths -ErrorAction Stop

foreach ( $configFile in $configFiles )
{
    # Build the path to the destination file
    $destinationFile = Join-Path -Path $Destination -ChildPath $configFile.Name

    # Determine if the file exists in the destination
    $destinationFileExists = Test-Path -Path $destinationFile

    if ( $debug )
    {
        $message = "`nFile: $($configFile.Name) `nDestination: $($destinationFile.FullName) `nFile Exists: $destinationFileExists"
        $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
        Write-Debug -Message $message
    }

    # If the file does not exist in the destionation OR if the file exists and force is true
    if ( ( $destinationFileExists -eq $false ) -or ( $destinationFileExists -and $forceCopy ) )
    {
        # Copy the file to the destination path
        $copyItemParams = @{
            Path = $configFile
            Destination = $destinationFile
            Force = $forceCopy
        }
        if ( $debug )
        {
            $copyItemParamsString = ( $copyItemParams.GetEnumerator() | ForEach-Object -Process { "`n$($_.Key) => $($_.Value)" } ) -join ''
            $message = "Copy-Item $copyItemParamsString"
            $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
            Write-Debug -Message $message
        }
        Copy-Item @copyItemParams
    }
}

# Log an event for script ending and total execution time.
$endTime = Get-Date
$scriptTime = ( $endTime - $startTime ).TotalSeconds

if ( $debug )
{
    $message = "`n Script Completed. `n Script Runtime: ($scriptTime) seconds."
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}
