# Set the verbose preference
$VerbosePreference = 'Continue'


# Download the System Center Visual Studio Authoring Extensions (VSAE)
$invokeWebRequestParams = @{
	Uri = 'https://download.microsoft.com/download/4/4/6/446B60D0-4409-4F94-9433-D83B3746A792/VisualStudioAuthoringConsole_x64.msi'
	OutFile = 'VisualStudioAuthoringConsole_x64.msi'
}
Invoke-WebRequest @invokeWebRequestParams

# Get the downloaded MSI file
$vsaeMsiFile = Get-Item -Path $invokeWebRequestParams.OutFile -ErrorAction Stop

# Install the VSAE
msiexec /quiet /i $vsaeMsiFile.FullName

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

	# Get the path to MS Build
	$msBuildExe = Get-Item -Path ( Join-Path -Path $vsinfo.installationPath -ChildPath 'MSBuild\Current\Bin\MSBuild.exe' ) -ErrorAction Stop
	Write-Verbose -Message "MSBuild.exe path: $($msBuildExe.FullName)"

	# Build the solution
	<#$devenvcomStartProcessArguments = @(
		$solution.FullName
		'/Build Release'
	)#>
	#Write-Verbose -Message "'$devenvexe' $($devenvcomStartProcessArguments -join ' ')"
	#Start-Process -FilePath $devenvexe.FullName -NoNewWindow -Wait -ArgumentList $devenvcomStartProcessArguments

	foreach ( $project in ( Get-ChildItem -Filter *.mpproj -Recurse ) )
	{
		# Build the solution
		$msBuildExeStartProcessArguments = @(
			$project.FullName
			'-t:build'
		)
		Write-Verbose -Message "'$($msBuildExe.FullName)' $($msBuildExeStartProcessArguments -join ' ')"
		Start-Process -FilePath $msBuildExe.FullName -NoNewWindow -Wait -ArgumentList $msBuildExeStartProcessArguments
	}

	Get-ChildItem -Path .\AlertManagement\bin -Recurse
}
