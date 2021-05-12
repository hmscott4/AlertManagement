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

$scriptName = 'New-ConfigurationFiles.ps1'
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

#region Create assign.alert.config
$assignAlertConfigXml = [System.Xml.XmlDocument] @'
<?xml version="1.0" encoding="utf-8"?>
<config version="2.0">
    <exceptions>
    <!-- Use exceptions to assign alerts to owners when more granular control is needed -->
    <!-- Exceptions should be ordered with the most narrow criteria first -->
    <!-- Exceptions are always processed before "assignments" -->
    <!-- Below are some sample exceptions which are disabled by default -->
    <!--   To use these examples, update the "AlertPropertyMatches" node and set "enabled" to "true" -->
	    <exception ID="10" Name="ServerOffline" Owner="EFG Windows Team" enabled="false">
	      <Alert Name="Health Service Heartbeat Failure" >
		    <AlertProperty>MonitoringObjectDisplayName</AlertProperty>
		    <AlertPropertyMatches>efg\.lcl</AlertPropertyMatches>
	      </Alert>
	    </exception>
	    <exception ID="20" Name="ServerOffline" Owner="EFG Windows Team" enabled="false">
	      <Alert Name="Failed to Connect to Computer" >
		    <AlertProperty>MonitoringObjectDisplayName</AlertProperty>
		    <AlertPropertyMatches>efg\.lcl</AlertPropertyMatches>
	      </Alert>
	    </exception>
	    <exception ID="30" Name="ServerOffline" Owner="Windows Team" enabled="false">
	      <Alert Name="Health Service Heartbeat Failure" />
	    </exception>
	    <exception ID="40" Name="Failed to Connect to Computer" Owner="Windows Team" enabled="false">
	      <Alert Name="Failed to Connect to Computer" />
	    </exception>
    </exceptions>
	<assignments>
    <!-- Use assignments to update Alert Ownership based on Management Pack -->
    <!-- A default configuration is prepared for you based on the management packs installed in your MG -->
    <!-- To update an assignment rule, move the entry with the management pack name to another owner -->
    <!-- To disable assignment for a particular group of management packs, set "enabled" to "false" -->
    <!-- Assignments are processed after exceptions -->
	</assignments>
</config>
'@

# Get the assign.alert.config file schema
$assignAlertConfigSchema = Get-Item -Path '$FileResource[Name="SCOM.Alert.Management.AssignAlertConfigSchema"]/Path$' -ErrorAction Stop
$assignAlertConfigXml.Schemas.Add('',$assignAlertConfigSchema.FullName) > $null

<#
Create an array of tuples with contains the following properties:
    Name
    Group
    Regular Expression
#>
$assignmentGroups = @()
$assignmentGroups += [System.Tuple]::Create('ADDS','Active Directory Team','\.AD\.')
$assignmentGroups += [System.Tuple]::Create('Exchange','Exchange Team','Exchange')
$assignmentGroups += [System.Tuple]::Create('Monitoring','Monitoring Team','SystemCenter')
$assignmentGroups += [System.Tuple]::Create('M365','M365 Team','365')
$assignmentGroups += [System.Tuple]::Create('NetworkServices','Network Team','DNSServer')
$assignmentGroups += [System.Tuple]::Create('Oracle','DBA Team','Oracle')
$assignmentGroups += [System.Tuple]::Create('PKI','PKI Team','Certificate')
$assignmentGroups += [System.Tuple]::Create('SharePoint','SharePoint Team','SharePoint')
$assignmentGroups += [System.Tuple]::Create('SQL','DBA Team','SQL')
$assignmentGroups += [System.Tuple]::Create('Unix','Linux Team','nix')
$assignmentGroups += [System.Tuple]::Create('Virtualization','Virtualization Team','HyperV')
$assignmentGroups += [System.Tuple]::Create('IIS','Web Team','InternetInformationServices')
$assignmentGroups += [System.Tuple]::Create('Windows','Windows Team','Windows(\.Cluster|\.Server|Defender|\.MSDTC|\.FileServer|\.Library)|File\.Share')
# Catch-all for unknown management packs
$assignmentGroups += [System.Tuple]::Create('Unassigned','Monitoring Team','')

# Get the installed management packs
$managementPacks = Get-SCOMManagementPack | Select-Object -ExpandProperty Name | Sort-Object

foreach ( $managementPack in $managementPacks)    
{
    foreach ( $assignmentGroup in $assignmentGroups )
    {
        # Get the assignment node if it exists
        $nodeSelectionQuery = "//config/assignments/assignment[@Name='$($assignmentGroup.Item1)'][@Owner='$($assignmentGroup.Item2)']"
        $assignmentNode = $assignAlertConfigXml.SelectSingleNode($nodeSelectionQuery)

        if ( -not $assignmentNode )
        {
            # Figure out the ID
            $id = (
                $assignAlertConfigXml.config.assignments.assignment.ID |
                ForEach-Object -Process { if ( $_ ) { [System.Int32]::Parse($_) } } |
                Sort-Object -Descending |
                Select-Object -First 1
            ) + 1

            # Create the assignment node
            $assignmentNode = $assignAlertConfigXml.CreateElement('assignment')
            $assignmentNode.SetAttribute('ID',$id)
            $assignmentNode.SetAttribute('Name',$assignmentGroup.Item1)
            $assignmentNode.SetAttribute('Owner',$assignmentGroup.Item2)
            $assignmentNode.SetAttribute('enabled','true')
            $assignmentNode = $assignAlertConfigXml.SelectSingleNode('/config/assignments').AppendChild($assignmentNode)
        }
        
        if ( $managementPack -match $assignmentGroup.Item3 )
        {
            $managementPackNode = $assignAlertConfigXml.CreateElement('ManagementPack')
            $managementPackNode.SetAttribute('Name',$managementPack)
            $managementPackNode = $assignAlertConfigXml.SelectSingleNode($nodeSelectionQuery).AppendChild($managementPackNode)
            
            # Prevent assigning a management pack to more than one group
            break
        }
    }
}

# Build the path to the assign.alert.config file
$assignAlertConfigFile = Join-Path -Path $Destination -ChildPath assign.alert.config

# Determine if the file exists in the destination
$assignAlertConfigFileExists = Test-Path -Path $assignAlertConfigFile

if ( $debug )
{
    $message = "`nFile: $($assignAlertConfigFile.Name) `nDestination: $($assignAlertConfigFile.FullName) `nFile Exists: $assignAlertConfigFileExists"
    $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
    Write-Debug -Message $message
}

# If the file does not exist in the destionation OR if the file exists and force is true
if ( ( $assignAlertConfigFileExists -eq $false ) -or ( $assignAlertConfigFileExists -and $forceCopy ) )
{
    # Validate the XML before saving
    $assignAlertConfigXml.Validate($null)
    
    if ( $debug )
    {
        $message = "Saving the $(Split-Path -Path $assignAlertConfigFile -Leaf) to '$($assignAlertConfigFile)'"
        $momapi.LogScriptEvent($scriptName, $scriptEventID, 0, $message)
        Write-Debug -Message $message
    }
    $assignAlertConfigXml.Save($assignAlertConfigFile)
}

#endregion Create assign.alert.config

# Define an array with the config files from the management pack
$configFilePaths = @(
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
