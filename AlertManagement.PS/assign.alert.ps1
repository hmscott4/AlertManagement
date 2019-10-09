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
# 2017/02/28   HMS    - Modified to write J64 - VDI to Custom Field 10
# 2018/02/20   HMS    - Modified to write Queue information to Owner field
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

			###### FIRST PASS; GET QUEUE ASSIGNMENT EXCEPTIONS BY ALERT NAME ######
			Try
			{
				$assignmentRule = $configFile.SelectSingleNode("
					//Config/Exceptions/Exception[
						AlertName='$alertName'
						and @enabled='true'
						and contains(
							'$($NewAlert.($assignmentRule.AlertProperty))',
							AlertPropertyContains
						)
					]"
				)
			}
			Catch [System.Exception]
			{
				$timeNow = Get-Date -f "yyyy/MM/dd hh:mm:ss"
				$msg = "$timeNow : WARN : " + $_.Exception.Message
				# Write-Host $msg
				Add-Content $unroutedLogFile $msg
			}

			if($assignmentRule)
			{
				[string]$assignedTo=$assignmentRule.Owner
			}
			else
			{
				###### SECOND PASS; GET ALERT ASSIGNMENTS FROM OBJECT CLASS ######
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

			# Define a comment for Set-SCOMAlert
			$comment = 'Alert automation assigned to: {0}'

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
		}
		}
	}