[CmdletBinding()]
param(
  [string] $Root = '.'
)

$ErrorActionPreference = 'Stop'
$builder = Join-Path $PSScriptRoot '..\skills\sysu-wechat-index-builder\scripts\build-indexes.ps1'
& $builder -Root $Root
