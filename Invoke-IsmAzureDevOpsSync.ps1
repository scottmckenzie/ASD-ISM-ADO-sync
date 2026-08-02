#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
  [Parameter(Mandatory)][string]$Organisation,
  [Parameter(Mandatory)][string]$Project,
  [string]$WorkItemType='Issue', [string]$AreaPath, [string]$IterationPath,
  [string]$Pat=$env:AZURE_DEVOPS_EXT_PAT,
  [string]$OscalUri='https://raw.githubusercontent.com/AustralianCyberSecurityCentre/ism-oscal/main/ISM_catalog.json',
  [string]$OscalPath,
  [string]$FieldMapPath=(Join-Path $PSScriptRoot 'field-map.example.json'),
  [switch]$MarkRetired, [switch]$IncludePrinciples, [switch]$Apply
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'src/IsmAzureDevOpsSync.psm1') -Force
if(-not $Apply){$WhatIfPreference=$true}
Sync-IsmAzureDevOps @PSBoundParameters -WhatIf:$WhatIfPreference -Confirm:$false
