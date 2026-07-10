# bootstrap-private.ps1 -- generic private repo clone dispatcher
#
# Clones a private repository (or pulls if already cloned) and executes
# a named script inside it. Extra arguments are forwarded to the target script.
#
# Usage:
#   bootstrap-private.ps1 -Repo <ssh-url> -Dest <parent-dir> -Run <script> [extra args...]
#
# Example one-liner:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/abuttaro-conga/Bootstrap-Public/main/bootstrap-private.ps1))) `
#     -Repo git@github.com:congaengr/Bootstrap-Private.git `
#     -Dest "$HOME\src\github\congaengr" `
#     -Run bootstrap.ps1

param(
  [Parameter(Mandatory = $true)]
  [string]$Repo,

  [Parameter(Mandatory = $true)]
  [string]$Dest,

  [Parameter(Mandatory = $true)]
  [string]$Run,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Run -match '\.\.') {
  throw "error: -Run must be a relative path with no '..'"
}

$repoName    = [IO.Path]::GetFileNameWithoutExtension($Repo.Split('/')[-1])
$cloneTarget = Join-Path $Dest $repoName

New-Item -ItemType Directory -Force -Path $Dest | Out-Null

if (Test-Path (Join-Path $cloneTarget ".git")) {
  Write-Host "Updating $cloneTarget"
  git -C $cloneTarget pull --ff-only
  if ($LASTEXITCODE -ne 0) { throw "git pull failed in $cloneTarget" }
} else {
  Write-Host "Cloning $Repo"
  git clone $Repo $cloneTarget
  if ($LASTEXITCODE -ne 0) { throw "git clone failed for $Repo" }
}

$targetScript = Join-Path $cloneTarget $Run
if (-not (Test-Path $targetScript)) {
  throw "Script not found: $targetScript"
}

& $targetScript @ExtraArgs
exit $LASTEXITCODE
