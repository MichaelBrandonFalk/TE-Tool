param(
    [Parameter(Mandatory = $false)]
    [string]$Version = "11.12"
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

# Bash needs the complete portable root for Windows drive mounts and /tmp.
Get-ChildItem $env:PORTABLE_GIT_ROOT -Force | Copy-Item `
    -Destination (Join-Path $PlatformResources "runtime") -Recurse -Force

function Convert-ToMsysPath([string]$PathValue) {
    $full = [System.IO.Path]::GetFullPath($PathValue).Replace("\", "/")
    if ($full -match "^([A-Za-z]):/(.*)$") {
        return "/$($Matches[1].ToLowerInvariant())/$($Matches[2])"
    }
    return $full
}

# Exercise the Windows Bash and media binaries against a real media file.
$SmokeDir = Join-Path $Work "smoke-test"
New-Item $SmokeDir -ItemType Directory -Force | Out-Null
New-Item (Join-Path $SmokeDir "logs") -ItemType Directory -Force | Out-Null
New-Item (Join-Path $SmokeDir "tmp") -ItemType Directory -Force | Out-Null
$SmokeMedia = Join-Path $SmokeDir "windows-smoke.mov"
$BundledFfmpeg = Join-Path $PlatformResources "ffmpeg.exe"
& $BundledFfmpeg -v error `
    -f lavfi -i "color=size=720x480:rate=30000/1001:color=black" `
    -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=48000" `
    -t 0.25 -shortest -c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le `
    -c:a pcm_s24le -ar 48000 -ac 2 $SmokeMedia
if ($LASTEXITCODE -ne 0) {
    throw "Bundled FFmpeg could not create the Windows smoke-test media."
}

$env:TE_NONINTERACTIVE = "1"
$env:TE_TEST_TYPE = "SVOD"
$env:TE_PHASE1_ON = "1"
$env:TE_IFRAME_ON = "0"
$env:TE_CAPTIONPROFANITY_ON = "0"
$env:TE_PHASE2_ON = "0"
$env:TE_LUMAIRE_ON = "0"
$env:TE_TRUEPEAKS_ON = "0"
$env:TE_ADVANCEDCONTINUITY_ON = "0"
$env:TE_ADVANCEDLUMAIRE_ON = "0"
$env:TE_ADVANCEDCHROMA_ON = "0"
$env:TE_LOG_DIR = Convert-ToMsysPath (Join-Path $SmokeDir "logs")
$env:TE_TMP_DIR = Convert-ToMsysPath (Join-Path $SmokeDir "tmp")
$env:FFMPEG_BIN = Convert-ToMsysPath (Join-Path $PlatformResources "ffmpeg.exe")
$env:FFPROBE_BIN = Convert-ToMsysPath (Join-Path $PlatformResources "ffprobe.exe")
$env:JQ_BIN = Convert-ToMsysPath (Join-Path $PlatformResources "jq.exe")
$env:EXIFTOOL_BIN = Convert-ToMsysPath (Join-Path $PlatformResources "exiftool.exe")
$BundledBash = Join-Path $PlatformResources "runtime\bin\bash.exe"
$SmokeLines = & $BundledBash `
    (Convert-ToMsysPath (Join-Path $Root "Resources\script")) `
    (Convert-ToMsysPath $SmokeMedia) 2>&1
$SmokeExitCode = $LASTEXITCODE
$SmokeOutput = $SmokeLines -join [Environment]::NewLine
Write-Host $SmokeOutput
if ($SmokeExitCode -ne 0) {
    throw "Windows media smoke test failed with exit code $SmokeExitCode."
}
foreach ($marker in @("VIDEO CODEC:", "FRAME RATE:", "AUDIO CODEC:", "Total TE processing time:")) {
    if (-not $SmokeOutput.Contains($marker)) {
        throw "Windows media smoke test did not report '$marker'."
    }
}

$env:TE_PLATFORM_RESOURCES = $PlatformResources
$env:TE_WINDOWS_ICON = $IconIco
pyinstaller --noconfirm --clean `
    --distpath $PyInstallerDist `
    --workpath (Join-Path $Work "pyinstaller-work") `
    (Join-Path $Root "cross_platform\te_tool.spec")
if ($LASTEXITCODE -ne 0) {
    throw "PyInstaller could not build the Windows desktop app."
}

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
