[CmdletBinding()]
param
()

$states = @{
	5 = 'Assigned'
	15 = 'Verified'
	18 = 'Alert Storm'
}
  
foreach ( $state in $states.GetEnumerator() )
{
	Add-SCOMResolutionState -Name $state.Value -ResolutionStateCode = $state.Key
}
