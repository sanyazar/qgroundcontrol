# Builds the QGroundControl-Bastion .msi on a Windows CI runner (GitLab shell executor).
# Prerequisites on the machine: Git, Python 3.12, uv, .NET SDK 8 and Visual Studio 2022 Build Tools
# (python tools\setup\install_dependencies --platform windows --msvc). Qt and WiX are installed on
# first use and reused afterwards.
param(
    [string]$BuildDir = (Join-Path (Get-Location) 'build-msi'),
    [string]$QtDir = 'C:\Qt',
    [string]$WixVersion = '5.0.2'
)

$ErrorActionPreference = 'Stop'

function Invoke-Native {
    param([string]$Name, [scriptblock]$Command)
    Write-Host "==> $Name"
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE"
    }
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# The runner service account does not see per-user installs (winget puts uv in the user's profile),
# so look in the usual places and otherwise install uv into a machine-wide tools folder.
function Resolve-Uv {
    $command = Get-Command uv -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    $toolsDir = Join-Path $env:SystemDrive 'ci-tools\uv'
    $candidates = @(
        (Join-Path $toolsDir 'uv.exe'),
        (Join-Path $env:USERPROFILE '.local\bin\uv.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\uv.exe')
    )
    $candidates += Get-ChildItem -Path (Join-Path $env:SystemDrive 'Users\*\.local\bin\uv.exe'), `
        (Join-Path $env:SystemDrive 'Users\*\AppData\Local\Microsoft\WinGet\Links\uv.exe') `
        -ErrorAction SilentlyContinue | ForEach-Object FullName
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }
    Write-Host "==> installing uv into $toolsDir"
    $env:UV_INSTALL_DIR = $toolsDir
    $env:UV_NO_MODIFY_PATH = '1'
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    $uvExe = Join-Path $toolsDir 'uv.exe'
    if (-not (Test-Path $uvExe)) {
        throw "uv installation failed: $uvExe not found"
    }
    return $uvExe
}
$uv = Resolve-Uv
Write-Host "Using uv: $uv"

# Locked Python environment for QGC's generators, aqtinstall and the pinned CMake/Ninja.
$venv = Join-Path $repo '.venv-ci'
$env:UV_PROJECT_ENVIRONMENT = $venv
$env:QGC_PYTHON_ENV = $venv
Invoke-Native 'python environment' {
    & $uv sync --project (Join-Path $repo 'tools') --python 3.12 --group scripts --group qt --group build `
        --no-default-groups --no-install-project --frozen
}
$python = Join-Path $venv 'Scripts\python.exe'

# Qt for MSVC, version from .github/build-config.json.
$qtVersion = (& $python (Join-Path $repo 'tools\setup\read_config.py') --get qt.version).Trim()
$qtRoot = Join-Path $QtDir "$qtVersion\msvc2022_64"
if (-not (Test-Path (Join-Path $qtRoot 'lib\cmake\Qt6\qt.toolchain.cmake'))) {
    Invoke-Native "Qt $qtVersion" {
        & $python (Join-Path $repo 'tools\setup\install_qt.py') install --from-config --host windows `
            --target desktop --arch win64_msvc2022_64 --outdir $QtDir
    }
}
$env:QT_ROOT_DIR = $qtRoot

# WiX Toolset (wix.exe) and the extensions CPack's WIX generator uses.
dotnet tool update --global wix --version $WixVersion
if ($LASTEXITCODE -ne 0) {
    Invoke-Native 'WiX install' { dotnet tool install --global wix --version $WixVersion }
}
$wix = Join-Path $env:USERPROFILE '.dotnet\tools\wix.exe'
foreach ($extension in 'WixToolset.UI.wixext', 'WixToolset.Util.wixext') {
    & $wix extension add -g "$extension/$WixVersion"
    if ($LASTEXITCODE -ne 0 -and -not ((& $wix extension list -g) -match [regex]::Escape($extension))) {
        throw "Failed to add WiX extension $extension"
    }
}

# MSVC x64 developer environment.
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) {
    throw 'Visual Studio Build Tools with VC tools not found'
}
cmd /c "`"$(Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat')`" >nul && set" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
    }
}
# vcvars prepends its own CMake/Ninja; keep the locked versions and wix.exe first.
$env:PATH = "$(Join-Path $venv 'Scripts');$(Split-Path $wix);$env:PATH"

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
Set-Location $repo
Invoke-Native 'configure' {
    cmake --preset Windows-msi -S $repo -B $BuildDir "-DPython3_EXECUTABLE=$python" -DQGC_ENABLE_GST_VIDEOSTREAMING=ON
}
Invoke-Native 'build' { cmake --build $BuildDir --config Release --parallel }
Invoke-Native 'package' { cmake --build $BuildDir --config Release --target qgc-package }

$packages = Get-ChildItem -Path $BuildDir -Filter '*.msi' -File
if (-not $packages) {
    throw "Packaging finished but no .msi was found in $BuildDir"
}
$packages | ForEach-Object { Write-Host "Package: $($_.FullName)" }
