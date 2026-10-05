<#
.SYNOPSIS
  Installs the Godot export templates for the pinned engine (Windows templates only).

.DESCRIPTION
  Downloads the official Godot_v<version>-stable_export_templates.tpz from
  github.com/godotengine/godot, verifies it against the pinned SHA-512 (from the release's
  published SHA512-SUMS.txt, the same file that pins runtime\Godot.exe in get_godot.ps1), and
  extracts the Windows templates into runtime\editor_data\export_templates\<version>.stable\, where
  the self-contained runtime (runtime\_sc_) looks for them. runtime\ is outside git. Needed for
  release exports (the release benchmark, a shipped .exe). Safe to re-run.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\get_export_templates.ps1
#>
param(
  [string]$RuntimeDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'runtime'),
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Pinned with the engine (scripts/get_godot.ps1): change together when upgrading.
$Version = '4.7.2'
$TpzName = "Godot_v$Version-stable_export_templates.tpz"
$TpzSha512 = 'ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079'
$Wanted = @('version.txt', 'windows_release_x86_64.exe', 'windows_debug_x86_64.exe', 'windows_release_x86_64_console.exe', 'windows_debug_x86_64_console.exe')

$ReleaseUrl = "https://github.com/godotengine/godot/releases/download/$Version-stable"
$Dest = Join-Path $RuntimeDir "editor_data\export_templates\$Version.stable"

if ((Test-Path (Join-Path $Dest 'windows_release_x86_64.exe')) -and -not $Force) {
  Write-Host "Export templates $Version are already installed at $Dest. Use -Force to reinstall."
  exit 0
}
if (-not (Test-Path (Join-Path $RuntimeDir '_sc_'))) { throw "runtime\ is not the self-contained engine: run scripts\get_godot.ps1 first." }

$work = Join-Path ([IO.Path]::GetTempPath()) ("get_templates_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $work | Out-Null
try {
  $tpz = Join-Path $work $TpzName
  Write-Host "Downloading $ReleaseUrl/$TpzName ..."
  Invoke-WebRequest "$ReleaseUrl/$TpzName" -OutFile $tpz -UseBasicParsing
  $actual = (Get-FileHash $tpz -Algorithm SHA512).Hash.ToLowerInvariant()
  if ($actual -ne $TpzSha512) { throw "Checksum mismatch for $TpzName.`n expected $TpzSha512`n actual   $actual" }
  Write-Host 'SHA-512 verified.'

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  New-Item -ItemType Directory -Force $Dest | Out-Null
  $zip = [IO.Compression.ZipFile]::OpenRead($tpz)
  try {
    foreach ($entry in $zip.Entries) {
      $name = Split-Path $entry.FullName -Leaf
      if ($Wanted -contains $name) {
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $Dest $name), $true)
        Write-Host "  $name"
      }
    }
  } finally { $zip.Dispose() }
  if (-not (Test-Path (Join-Path $Dest 'windows_release_x86_64.exe'))) { throw "windows_release_x86_64.exe was not in $TpzName." }
  Write-Host "Installed the Windows export templates for $Version at $Dest"
}
finally {
  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}
