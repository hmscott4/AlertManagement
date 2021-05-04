# Set the verbose preference
$VerbosePreference = 'Continue'

Write-Verbose -Message "GITHUB_REF: $env:GITHUB_REF"
Write-Verbose -Message "GITHUB_HEAD_REF: $env:GITHUB_HEAD_REF"
Write-Verbose -Message "GITHUB_BASE_REF: $env:GITHUB_BASE_REF"

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

	foreach ( $projectFile in ( Get-ChildItem -Filter *.mpproj -Recurse ) )
	{
		# Get the next management pack version from the user file
		$projectUserFile = Get-ChildItem -Path $projectFile.Directory -Filter *.mpproj.user
		$projectUserFileXml = [System.Xml.XmlDocument] ( $projectUserFile | Get-Content )
		$nextVersion = [System.Version]::new($projectUserFileXml.Project.PropertyGroup.DeploymentNextVersion)
		Write-Verbose -Message "Current Management Pack Version: $($nextVersion.ToString())"
		
		# Break out the version components to make it easier to work with
		$nextVersionMajor = $nextVersion.Major
		$nextVersionMinor = $nextVersion.Minor
		$nextVersionBuild = $nextVersion.Build
		$nextVersionRevision = $nextVersion.Revision

		# Increment the minor version
		if ( ( $env:GITHUB_REF -match '^refs/heads/dev' ) -and $env:GITHUB_HEAD_REF -and $env:GITHUB_BASE_REF )
		{
			$nextVersionMinor++
		}

		# Increment the major version
		if ( ( $env:GITHUB_REF -match '^refs/heads/main' ) -and $env:GITHUB_HEAD_REF -and $env:GITHUB_BASE_REF )
		{
			$nextVersionMajor++
			$nextVersionMinor = 0
		}

		# Increment the build
		$nextVersionBuild++

		# Create the new version
		$newVersion = [System.Version]::new($nextVersionMajor,$nextVersionMinor,$nextVersionBuild,$nextVersionRevision)
		Write-Verbose -Message "New Management Pack Version: $($newVersion.ToString())"

		# Set the next management pack version in the project file
		$projectFileXml = [System.Xml.XmlDocument] ( $projectFile | Get-Content )
		$mpConfiguration = $projectFileXml.Project.PropertyGroup | Where-Object -FilterScript { [System.String]::IsNullOrEmpty($_.Condition) }
		$mpConfiguration.Version = $newVersion.ToString()
		$projectFileXml.Save($projectFile.FullName)

		# Increment the version in the user file
		$newNextVersion = [System.Version]::new($newVersion.Major,$newVersion.Minor,$newVersion.Build, $newVersion.Revision + 1)
		$projectUserFileXml.Project.PropertyGroup.DeploymentNextVersion = $newNextVersion.ToString()
		$projectUserFileXml.Save($projectUserFile.FullName)

		# Build the project
		$msBuildExeStartProcessArguments = @(
			$projectFile.FullName
			'-t:build'
			'-property:Configuration=Release'
		)
		Write-Verbose -Message "'$($msBuildExe.FullName)' $($msBuildExeStartProcessArguments -join ' ')"
		Start-Process -FilePath $msBuildExe.FullName -NoNewWindow -Wait -ArgumentList $msBuildExeStartProcessArguments
	}

	# Verify the management pack files were created
	$releaseFiles = Get-ChildItem -Path .\AlertManagement\bin\Release | Where-Object -FilterScript { $_.Extension -match 'mpb' }
	if ( -not $releaseFiles )
	{
		throw 'No management pack files found in ".\AlertManagement\bin\Release"'
	}
	else
	{
		# Return the version to GitHub
		Write-Output -InputObject "Version=$($newVersion.ToString())" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append

		# Zip up the management pack files
		Compress-Archive -Path $releaseFiles.FullName -Destination AlertManagement.zip
	}
}
