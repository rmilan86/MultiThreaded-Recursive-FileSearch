\
param(
  [Parameter(Mandatory=$false)]
  [string]$Root = ".."
)

# ------------------------------------------------------------
#  MultiThreaded Recursive FileSearch - GPL Header Inserter (Delphi)
#  - Adds a GPLv3 header block to .pas and .dpr files
#  - Skips files that already contain "GNU General Public License"
#  - Uses tools/add-gpl-headers-config.json for project/author info
# ------------------------------------------------------------

$ConfigPath = Join-Path $PSScriptRoot "add-gpl-headers-config.json"

if (-not (Test-Path $ConfigPath)) {
  Write-Host "Config file not found: $ConfigPath"
  exit 1
}

$ConfigJson = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$ProjectName   = $ConfigJson.projectName
$AuthorName    = $ConfigJson.authorName
$AuthorWebsite = $ConfigJson.authorWebsite
$Year          = $ConfigJson.year
$LicenseName   = $ConfigJson.licenseName

function Get-GplHeader([string]$FileName) {

  $Header = @"
(************************************************************
     Project: $ProjectName
     File: $FileName
     Author: $AuthorName ($AuthorWebsite)
     License: $LicenseName

     Copyright (c) $Year $AuthorName ($AuthorWebsite)

     This program is free software: you can redistribute it and/or modify
     it under the terms of the GNU General Public License as published by
     the Free Software Foundation, either version 3 of the License, or
     (at your option) any later version.

     This program is distributed in the hope that it will be useful,
     but WITHOUT ANY WARRANTY; without even the implied warranty of
     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
     GNU General Public License for more details.

     You should have received a copy of the GNU General Public License
     along with this program.  If not, see <https://www.gnu.org/licenses/>.
************************************************************)

"@

  return $Header
}

$RootFull = Resolve-Path (Join-Path $PSScriptRoot $Root)

Write-Host "Root: $RootFull"
Write-Host "Scanning for Delphi sources (.pas, .dpr)..."

$Files = Get-ChildItem -Path $RootFull -Recurse -File |
         Where-Object { $_.Extension -in @(".pas", ".dpr") }

foreach ($File in $Files) {

  $Text = Get-Content $File.FullName -Raw

  # Skip if already has GPL text
  if ($Text -match "GNU General Public License") {
    Write-Host "SKIP (already has GPL): $($File.FullName)"
    continue
  }

  # Skip empty files
  if ([string]::IsNullOrWhiteSpace($Text)) {
    Write-Host "SKIP (empty): $($File.FullName)"
    continue
  }

  $Header = Get-GplHeader $File.Name
  $NewText = $Header + $Text

  Set-Content -Path $File.FullName -Value $NewText -Encoding UTF8

  Write-Host "ADD: $($File.FullName)"
}

Write-Host "Done."
