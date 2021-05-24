# Set the verbose preference
$VerbosePreference = 'Continue'

Write-Verbose -Message "GITHUB_BASE_REF: $($env:GITHUB_BASE_REF)"
Write-Verbose -Message "GITHUB_HEAD_REF: $($env:GITHUB_HEAD_REF)"

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

$solutions = Get-ChildItem -Path head -Filter *.sln -Recurse
Write-Verbose -Message ( "Solution Files: `n  {0}" -f ( $solutions.FullName -join "`n  " ) )

foreach ( $solution in $solutions )
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

	foreach ( $projectFile in ( Get-ChildItem -Path $solution.Directory -Filter *.mpproj -Recurse ) )
	{
		$projectFileXml = [System.Xml.XmlDocument] ( $projectFile | Get-Content )
		$managementPackName = $projectFileXml.Project.PropertyGroup | Where-Object -Property Name -NE 'PropertyGroup' | Select-Object -ExpandProperty Name
		Write-Output -InputObject "ManagementPackName=$managementPackName" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
		Write-Verbose -Message "Management Pack Name: $managementPackName"
		
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

		Write-Verbose -Message "Branch: $env:GITHUB_BASE_REF"
		switch -Regex ( $env:GITHUB_BASE_REF )
		{
			# Increment the minor version
			'^dev'
			{
				$commitComment = 'Incrementing minor version'
				$nextVersionMinor++
			}

			# Increment the major version
			'^main'
			{
				$commitComment = 'Incrementing major version'
				$nextVersionMajor++
				$nextVersionMinor = 0
			}
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
	$buildFiles = Get-ChildItem -Path .\head\*\*\bin\Release\*
	Write-Verbose -Message ( "Management Pack Files:`n  {0}" -f ( $buildFiles.FullName -join "`n  " ) )

	# Find the relevant file to release
	if ( $buildFiles.Extension -contains '.mpb' )
	{
		$releaseFile = $buildFiles | Where-Object -Property Extension -EQ .mpb
	}
	elseif ( $buildFiles.Extension -contains '.mp' )
	{
		$releaseFile = $buildFiles | Where-Object -Property Extension -EQ .mp
	}
	else
	{
		$releaseFile = $buildFiles | Where-Object -Property Extension -EQ .xml
	}

	if ( -not $releaseFile )
	{
		throw 'No management pack files found in ".\head\*\*\bin\Release\*"'
	}
	else
	{
		# Return the version to GitHub
		Write-Output -InputObject "Version=$($newVersion.ToString())" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append

		# Create the file name
		Write-Output -InputObject "ArtifactFileName=$($releaseFile.FullName)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
	}

	# Commit the version update to the reference repo
	Push-Location
	Set-Location -Path head
	git config user.name "GitHub Actions Bot"
	git config user.email "<>"
	git add $projectFile.FullName
	git add $projectUserFile.FullName
	git commit -m $commitComment
	git push
	Pop-Location
}
