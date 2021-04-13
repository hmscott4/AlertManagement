# Set the verbose preference
$VerbosePreference = 'Continue'

# Locate vswhere.exe
$vsWherePath = Join-Path -Path ( Join-Path -Path ( Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Microsoft Visual Studio' ) -ChildPath Installer ) -ChildPath vswhere.exe
Write-Verbose -Message "vswhere.exe path: $vsWherePath"
