# Entrypoint of deploy/docker/Dockerfile.windows: configures, builds and packages QGroundControl as an .msi.
# Expects the source tree at C:\project\source and writes to C:\project\build (both bind-mounted).
param(
    [string]$SourceDir = 'C:\project\source',
    [string]$BuildDir = 'C:\project\build',
    [string]$Preset = 'Windows-msi'
)

$ErrorActionPreference = 'Stop'

function Invoke-Step {
    param([string]$Name, [scriptblock]$Command)
    Write-Host "==> $Name"
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

# Import the MSVC x64 developer environment into this PowerShell session.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) {
    throw 'Visual Studio Build Tools with VC tools not found'
}
$vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
cmd /c "`"$vcvars`" >nul && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
    }
}
# vcvars prepends its own CMake/Ninja; keep the locked versions first.
$env:PATH = "C:\qgc-venv\Scripts;$env:PATH"

if (-not (Test-Path (Join-Path $SourceDir 'CMakeLists.txt'))) {
    throw "No QGroundControl source at $SourceDir; mount it with -v <repo>:$SourceDir"
}
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
Set-Location $SourceDir

Invoke-Step 'configure' {
    cmake --preset $Preset -S $SourceDir -B $BuildDir "-DPython3_EXECUTABLE=C:\qgc-venv\Scripts\python.exe"
}
Invoke-Step 'build' { cmake --build $BuildDir --config Release --parallel }
Invoke-Step 'package' { cmake --build $BuildDir --config Release --target qgc-package }

$packages = Get-ChildItem -Path $BuildDir -Filter '*.msi' -File
if (-not $packages) {
    throw "Packaging finished but no .msi was found in $BuildDir"
}
$packages | ForEach-Object { Write-Host "Package: $($_.FullName)" }
