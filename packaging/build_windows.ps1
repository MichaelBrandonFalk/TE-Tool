param(
    [Parameter(Mandatory = $false)]
    [string]$Version = "11.11"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Dist = Join-Path $Root "dist"
$Work = Join-Path $Dist "windows-build-work"
$PlatformResources = Join-Path $Work "platform-resources"
$PyInstallerDist = Join-Path $Work "pyinstaller-dist"
$InstallerOutput = Join-Path $Work "installer"
$Output = Join-Path $Dist "TE-Tool-Version-$Version-Windows-x64-Setup.exe"

$requiredEnvironment = @("PORTABLE_GIT_ROOT", "FFMPEG_ROOT", "EXIFTOOL_ROOT", "JQ_EXE")
foreach ($name in $requiredEnvironment) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "$name must point to an extracted build dependency."
    }
}

Remove-Item $Work -Recurse -Force -ErrorAction SilentlyContinue
New-Item $PlatformResources -ItemType Directory -Force | Out-Null
New-Item (Join-Path $PlatformResources "runtime") -ItemType Directory -Force | Out-Null
New-Item $InstallerOutput -ItemType Directory -Force | Out-Null

$IconIco = Join-Path $Work "te-tool.ico"
python -c "from PIL import Image; image=Image.open(r'$Root\docs\app-icon.png').convert('RGBA'); image.save(r'$IconIco', sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])"

pyinstaller --noconfirm --clean --onefile --console `
    --name "cussbuster" `
    --distpath (Join-Path $Work "cussbuster-dist") `
    --workpath (Join-Path $Work "cussbuster-work") `
    --specpath (Join-Path $Work "cussbuster-spec") `
    (Join-Path $Root "Resources\Cussbuster2000.py")

Copy-Item (Join-Path $Root "docs\app-icon.png") $PlatformResources
Copy-Item (Join-Path $Root "TE TOOLS User Manual.pdf") $PlatformResources
Copy-Item (Join-Path $Root "Installation Instructions.pdf") $PlatformResources
Copy-Item (Join-Path $Root "cross_platform\README-Windows.txt") $PlatformResources
Copy-Item (Join-Path $Root "packaging\THIRD_PARTY_NOTICES.txt") $PlatformResources
Copy-Item (Join-Path $Work "cussbuster-dist\cussbuster.exe") $PlatformResources
Copy-Item $env:JQ_EXE (Join-Path $PlatformResources "jq.exe")

$ffmpegBin = Get-ChildItem $env:FFMPEG_ROOT -Directory -Recurse | Where-Object { Test-Path (Join-Path $_.FullName "ffmpeg.exe") } | Select-Object -First 1
if ($null -eq $ffmpegBin) {
    throw "ffmpeg.exe was not found below FFMPEG_ROOT."
}
Copy-Item (Join-Path $ffmpegBin.FullName "ffmpeg.exe") $PlatformResources
Copy-Item (Join-Path $ffmpegBin.FullName "ffprobe.exe") $PlatformResources
Get-ChildItem $ffmpegBin.FullName -Filter "*.dll" | Copy-Item -Destination $PlatformResources

$exiftoolExe = Get-ChildItem $env:EXIFTOOL_ROOT -Filter "exiftool*.exe" -Recurse | Select-Object -First 1
if ($null -eq $exiftoolExe) {
    throw "ExifTool executable was not found below EXIFTOOL_ROOT."
}
Copy-Item $exiftoolExe.FullName (Join-Path $PlatformResources "exiftool.exe")
$exiftoolFiles = Get-ChildItem $env:EXIFTOOL_ROOT -Directory -Filter "exiftool_files" -Recurse | Select-Object -First 1
if ($null -ne $exiftoolFiles) {
    Copy-Item $exiftoolFiles.FullName (Join-Path $PlatformResources "exiftool_files") -Recurse
}

Copy-Item (Join-Path $env:PORTABLE_GIT_ROOT "usr") (Join-Path $PlatformResources "runtime\usr") -Recurse

$env:TE_PLATFORM_RESOURCES = $PlatformResources
$env:TE_WINDOWS_ICON = $IconIco
pyinstaller --noconfirm --clean `
    --distpath $PyInstallerDist `
    --workpath (Join-Path $Work "pyinstaller-work") `
    (Join-Path $Root "cross_platform\te_tool.spec")

$AppDir = Join-Path $PyInstallerDist "te-tool"
Copy-Item (Join-Path $Root "TE TOOLS User Manual.pdf") $AppDir
Copy-Item (Join-Path $Root "Installation Instructions.pdf") $AppDir
Copy-Item (Join-Path $Root "cross_platform\README-Windows.txt") $AppDir
Copy-Item (Join-Path $Root "packaging\THIRD_PARTY_NOTICES.txt") $AppDir

$selfTest = Start-Process -FilePath (Join-Path $AppDir "te-tool.exe") -ArgumentList "--self-test" -Wait -PassThru
if ($selfTest.ExitCode -ne 0) {
    throw "Packaged Windows runtime self-test failed with exit code $($selfTest.ExitCode)."
}

$IsccCommand = Get-Command "iscc.exe" -ErrorAction SilentlyContinue
if ($null -ne $IsccCommand) {
    $IsccPath = $IsccCommand.Source
} else {
    $fallback = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    if (Test-Path $fallback) {
        $IsccPath = $fallback
    } else {
        throw "Inno Setup 6 (iscc.exe) was not found."
    }
}

$InstallerScript = Join-Path $Root "cross_platform\windows\installer.iss"
& $IsccPath "/DMyAppVersion=$Version" "/DMyAppSourceDir=$AppDir" "/DMyAppIcon=$IconIco" "/DMyOutputDir=$InstallerOutput" $InstallerScript

$BuiltInstaller = Join-Path $InstallerOutput "TE-Tool-Version-$Version-Windows-x64-Setup.exe"
if (-not (Test-Path $BuiltInstaller)) {
    throw "Inno Setup did not create the expected installer."
}
Copy-Item $BuiltInstaller $Output -Force
Get-FileHash $Output -Algorithm SHA256
