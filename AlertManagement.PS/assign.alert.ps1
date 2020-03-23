########################################################################
# Assign-SCOMAlert.ps1
# Hugh Scott
# 2016/05/09
#
# Description:
#   Assign SCOM alerts based on rules in config file.  Basic assignment
# is done by management pack association.
#
# NOTE: The configuration file must be updated with entries from the current
# Active Directory environment.
#
# THIS CODE IS PROVIDED AS-IS WITH NO WARRANTIES EITHER EXPRESSED OR
# IMPLIED.
#
# Modifications:
# Date         Initials    Description
# 2016/05/09   HMS         -Original
# 2018/02/20   HMS         - Modified to write Queue information to Owner field
# 2019/10/09   HMS         - Significant re-write; added variables for Resolution State, Default Owner and Log Level
#
########################################################################

function XpathExpression {
param (
    [string]$value
)

    if ($value.Contains("'"))
    {
       return '\' + $value + '\';
    }
    elseif ($value.Contains('\'))
    {
       return """" + $value + """"
    }
    else
    {
       return $value;
    }
}

                  # Constants section - modify stuff here:
                  #=================================================================================
                  # Assign script name variable for use in event logging.
                  # ScriptName should be the same as the ID of the module that the script is contained in
                  $ScriptName = "Microsoft.Alert.Management.Alert.Management.Assign.Alert.TimedPowerShell.Rule.WA.ps1"
                  $EventID = "9931"
                  #=================================================================================


                  # Starting Script section - All scripts get this
                  #=================================================================================
                  # Gather the start time of the script
                  $StartTime = Get-Date
                  #Set variable to be used in logging events
                  $whoami = whoami
                  # Load MOMScript API
                  $momapi = New-Object -comObject MOM.ScriptAPI
                  #Log script event that we are starting task
                  $momapi.LogScriptEvent($ScriptName,$EventID,0,"`n Script is starting. `n Running as ($whoami).")
                  #=================================================================================

#region Initialize
[xml]$configFile= Get-Content '.\assign.alert.config' -ErrorAction SilentlyContinue
If($null -eq $configFile){
	# Write an Error log entry
	# quit
}
Else
{
	$managementGroup=$configFile.Config.Settings.ManagementGroup
	# [string]$managementServer = '.'

	## LOGGING
	[string]$logPath=$configFile.Config.Settings.Logging.OutputPath
	[int]$logLevel=$configFile.Config.Settings.Logging.LogLevel

	[string]$logFileDate = (Get-Date).ToString("yyyy.MM")

	[string]$logFile = "$logPath\AssignAlerts.$logFileDate.log"

	[string]$unroutedLogFile = "$logPath\MissedAlerts.$logFileDate.log"

	## DEFAULT VALUES

	## Unassigned Alerts
	[string]$defaultUnassignedOwner=$configFile.Config.Settings.Defaults.UnAssigned.DefaultOwner
	[int]$defaultUnassignedResolutionState=$configFile.Config.Settings.Defaults.UnAssigned.ResolutionState
	[string]$defaultUnassignedResolutionStateName=$configFile.Config.Settings.Defaults.UnAssigned.ResolutionStateName

	## Assigned alerts
	[int]$defaultAssignedResolutionState=$configFile.Config.Settings.Defaults.Assigned.ResolutionState
	[string]$defaultAssignedResolutionState=$configFile.Config.Settings.Defaults.Assigned.ResolutionStateName

#endregion

#region Connect
	Import-Module OperationsManager
	foreach($server in $managementGroup.ChildNodes)
	{
		If($server.Active -eq "true")
		{
			$connection = New-SCManagementGroupConnection $server.name -PassThru -ErrorAction SilentlyContinue
			If($connection.IsActive -eq $true)
			{
				Break
			}
		}
	}

	If($connection.IsActive -eq $false)
	{
		# Log an error
		# Exit
	}
	Else
	{
#endregion

		######### GET ALL ALERTS IN RESOLUTION STATE 0 ############
		$NewAlerts=Get-SCOMAlert -ResolutionState 0

		ForEach($NewAlert in $NewAlerts){
			# $unAssignedAlert = $NewAlert
			$mpClassId = $NewAlert.MonitoringClassId
			$mpClass = Get-SCOMClass -Id $mpClassId


			###### VARIABLE ASSIGNMENT ######
			[string]$mpName = $mpClass.ManagementPackName
			[string]$alertName = $NewAlert.Name
			[string]$displayName = $NewAlert.MonitoringObjectDisplayName

			$alertName = XPathExpression $AlertName

			#region Exceptions by Alert Name
			###### FIRST PASS; GET QUEUE ASSIGNMENT EXCEPTIONS BY ALERT NAME ######
			Try
			{
				$searchString = "//Config/Exceptions/Exception[AlertName='$alertName' and @enabled='true' "

				$assignmentRule = $configFile.SelectSingleNode($searchString)
			}
			Catch [System.Exception]
			{
				$timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
				$msg = "$timeNow : WARN : " + $_.Exception.Message
				# Write-Host $msg
				Add-Content $unroutedLogFile $msg
			}
			#endregion

			#region Exceptions By MP Name
			###### SECOND PASS; GET QUEUE ASSIGNMENT EXCEPTIONS BY MP NAME ######
			if($assignmentRule)
			{
				[string]$assignedTo=$assignmentRule.Owner
			}
			Else
			{
				Try
				{
				$searchString = @(
					"//Config/Exceptions/Exception[ManagementPackName='$mpName' and @enabled='true' "
				   " and ("
				   "     AlertProperty = 'MonitoringObjectFullName' "
				   "     or AlertProperty = 'MonitoringObjectPath' "
				   "     or AlertProperty = 'MonitoringObjectDisplayName' "
				   "  )]"
				)

				$assignmentRule = $configFile.SelectSingleNode($searchString)
				$Prop = $assignmentRule.AlertProperty
				$PropValue = $assignmentRule.AlertPropertyContains

				If($newAlert."$Prop" -notlike "*$AlertPropertyContains*")
				{
					$assignmentRule = $null
				}
				}
				Catch [System.Exception]
				{
					$timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
					$msg = "$timeNow : WARN : " + $_.Exception.Message
					# Write-Host $msg
					Add-Content $unroutedLogFile $msg
				}
			}
			#endregion

			#region Rules
			if($assignmentRule)
			{
				[string]$assignedTo=$assignmentRule.Owner
			}
			else
			{
				###### THIRD PASS; GET ALERT ASSIGNMENTS FROM OBJECT CLASS ######
				Try
				{
					$assignmentRule = $configFile.SelectSingleNode("
						//Config/Rules/Rule[managementPackName='$mpName' and @enabled='true']"
					)
				}
				Catch [System.Exception]
				{
					$timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
					$msg = "$timeNow : WARN : " + $_.Exception.Message
					# Write-Host $msg
					Add-Content $unroutedLogFile $msg
				}

				if ($assignmentRule)
				{
					[string]$assignedTo=$assignmentRule.Owner
				}
				else
				{
					[string]$assignedTo=$defaultUnassignedOwner
				}
			}
			#endregion

			#region Set Alert
			# Define a comment for Set-SCOMAlert
			[string]$comment = 'Alert automation assigned to: {0}'

			If($assignedTo -ne $defaultUnassignedOwner)
			{
				######## WRITE UPDATE TO ALERT ########
				$NewAlert | Set-SCOMAlert -ResolutionState $defaultAssignedResolutionState -Owner $assignedTo -Comment ( $comment -f $assignedTo )
        
				# Write-LogEntry
				If($logLevel -ge 2)
				{
					$timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
					$msg = "$timeNow : INFO : DisplayName: $displayName; AlertName: $alertName; Management Pack: $mpName; Owner: $assignedTo"
					# Write-Host $msg
					Add-Content $logFile $msg
				}
			}
			else
			{
				####### UNASSIGNED ALERTS #######
				$NewAlert | Set-SCOMAlert -ResolutionState $defaultUnassignedResolutionState -Owner $defaultUnassignedOwner -Comment ( $comment -f $defaultUnassignedOwner )
				# Write-LogEntry
				$timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
				$msg = "$timeNow : WARN : DisplayName: $displayName; AlertName: $alertName; Management Pack: $mpName; Owner: $defaultUnassignedOwner"
				# Write-Host $msg
				Add-Content $unroutedLogFile $msg
			}
			#endregion
		}
	}
}

                  # End of script section
                  #=================================================================================
                  #Log an event for script ending and total execution time.
                  $EndTime = Get-Date
                  $ScriptTime = ($EndTime - $StartTime).TotalSeconds
                  $momapi.LogScriptEvent($ScriptName,9931,0,"`n Script Completed. `n Script Runtime: ($ScriptTime) seconds.")
                  #=================================================================================
                  # End of script