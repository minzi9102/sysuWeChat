[CmdletBinding()]
param(
  [string] $Root = '.',
  [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
$repairer = Join-Path $PSScriptRoot '..\skills\sysu-wechat-index-builder\scripts\repair-indexes.ps1'
& $repairer @PSBoundParameters
