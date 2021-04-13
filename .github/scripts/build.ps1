# Set the verbose preference
$VerbosePreference = 'Continue'

# Locate vswhere.exe
$vsWherePath = Join-Path -Path ( Join-Path -Path ( Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Microsoft Visual Studio' ) -ChildPath Installer ) -ChildPath vswhere.exe
Write-Verbose -Message "vswhere.exe path: $vsWherePath"

foreach ( $solution in ( Get-ChildItem -Filter *.sln ) )
{
	# Get the Visual Studio version from the solution file
	$solutionFileContent = $solution | Get-Content
	$solutionFileVersion = $solutionFileContent |
		Where-Object -FilterScript { $_ -match '^VisualStudioVersion' } |
		ForEach-Object -Process { $_.Split('=')[1].Trim().Split('.')[0,1] -join '.' } |
		Sort-Object -Descending |
		Select-Object -First 1
	Write-Verbose -Message "Visual Studio solution version: $solutionFileVersion"

	# Get the Visual Studio installation information
	$vsInfo = & $vsWherePath -version $solutionFileVersion -latest -format json | ConvertFrom-Json
	Write-Verbose -Message "Visual Studio installation path: $($vsInfo.installationPath)"

	# Get the path to devenv.exe
	$devenvexe = Get-Item -Path $vsInfo.productPath
	Write-Verbose -Message "devenv.exe path: $($devenvexe.FullName)"

	# Build the solution
	$devenvcomStartProcessArguments = @(
		$solution.FullName
		'/Build Release'
	)
	Write-Verbose -Message "'$devenvexe' $($devenvcomStartProcessArguments -join ' ')"
	Start-Process -FilePath $devenvexe.FullName -NoNewWindow -Wait -ArgumentList $devenvcomStartProcessArguments
}
