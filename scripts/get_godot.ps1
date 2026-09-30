<#
.SYNOPSIS
  Downloads the pinned Godot engine into runtime\ (Windows, standard non-.NET build).

.DESCRIPTION
  Fetches the official release zip from github.com/godotengine/godot, verifies it
  against the pinned SHA-512 (taken from the release's published SHA512-SUMS.txt),
  and installs it as runtime\Godot.exe with the license files and the _sc_
  self-contained marker. Safe to re-run: if the pinned version is already present
  it does nothing unless -Force is given.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\get_godot.ps1
#>
param(
  [string]$RuntimeDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime'),
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar in PowerShell 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Pinned engine. To upgrade, change all three values together (hash from the release's SHA512-SUMS.txt).
$Version = '4.7.2'
$ZipName = "Godot_v$Version-stable_win64.exe.zip"
$ZipSha512 = '83decd58fdf67b9d657958a1ae6bf1929c20785315a81effe245874cdc57acb709bf868e00778a96984338c1b29dafdb453c6847747694621c6ecf5da2259993'

$Tag = "$Version-stable"
$ReleaseUrl = "https://github.com/godotengine/godot/releases/download/$Tag"
$RawUrl = "https://raw.githubusercontent.com/godotengine/godot/$Tag"
$Exe = Join-Path $RuntimeDir 'Godot.exe'

if ((Test-Path $Exe) -and -not $Force) {
  $current = (Get-Item $Exe).VersionInfo.ProductVersion
  if ($current -eq "$Version.stable.official") {
    Write-Host "Godot $Version is already installed at $Exe. Use -Force to reinstall."
    exit 0
  }
  Write-Host "Found Godot '$current' but $Version is pinned; replacing it."
}

New-Item -ItemType Directory -Force $RuntimeDir | Out-Null
$work = Join-Path ([IO.Path]::GetTempPath()) ("get_godot_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
try {
  $zip = Join-Path $work $ZipName
  Write-Host "Downloading $ReleaseUrl/$ZipName ..."
  Invoke-WebRequest "$ReleaseUrl/$ZipName" -OutFile $zip -UseBasicParsing

  $actual = (Get-FileHash $zip -Algorithm SHA512).Hash.ToLowerInvariant()
  if ($actual -ne $ZipSha512) {
    throw "Checksum mismatch for $ZipName.`n expected $ZipSha512`n actual   $actual"
  }
  Write-Host 'SHA-512 verified.'

  Expand-Archive $zip -DestinationPath $work -Force
  $extracted = Join-Path $work "Godot_v$Version-stable_win64.exe"
  if (-not (Test-Path $extracted)) { throw "Expected $extracted inside the zip." }

  # Stage next to the target and swap, so an interrupted run never leaves a half-written Godot.exe.
  $staged = "$Exe.new"
  Copy-Item $extracted $staged -Force
  Move-Item $staged $Exe -Force

  Invoke-WebRequest "$RawUrl/LICENSE.txt" -OutFile (Join-Path $RuntimeDir 'GODOT-LICENSE.txt') -UseBasicParsing
  Invoke-WebRequest "$RawUrl/COPYRIGHT.txt" -OutFile (Join-Path $RuntimeDir 'GODOT-COPYRIGHT.txt') -UseBasicParsing

  # _sc_ makes Godot self-contained (editor settings stay in runtime\); .gdignore hides runtime\ from the project.
  foreach ($marker in '_sc_', '.gdignore') {
    $path = Join-Path $RuntimeDir $marker
    if (-not (Test-Path $path)) { New-Item -ItemType File $path | Out-Null }
  }

  Write-Host "Installed Godot $((Get-Item $Exe).VersionInfo.ProductVersion) at $Exe"
}
finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
