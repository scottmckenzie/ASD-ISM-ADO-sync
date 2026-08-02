# ASD ISM Azure DevOps updater

PowerShell 7 utility that synchronises ASD ISM controls from the published OSCAL JSON catalog into Azure DevOps work items. It defaults to a safe preview and updates only mapped fields.

## Preview

```powershell
./Invoke-IsmAzureDevOpsSync.ps1 `
  -Organisation 'my-organisation' `
  -Project 'ISM Controls' `
  -WorkItemType 'Issue'
```

Add `-Apply` to write changes. Authenticate with `AZURE_DEVOPS_EXT_PAT`, `-Pat`, or an existing `az login` session. Use `-OscalPath ./ISM_catalog.json` for a reviewed local catalog, `-MarkRetired` to tag removed controls without deleting them, and `-IncludePrinciples` to import ISM principles.

Copy `field-map.example.json` to map custom Azure DevOps fields. Supported sources are `Id`, `Title`, `Statement`, `Revision`, `Updated`, `Applicability`, `Guideline`, `Section`, and `Class`.

Managed work items are matched using the tags `ASD-ISM-Managed` and `ASD-ISM-ID:ism-NNNN`. Existing work items must receive those tags before the first applied run; title-based matching is intentionally avoided to prevent unintended edits.

## Durable storage

This folder is a synced ChatGPT project mirror and may be refreshed when a new task starts. Copy the updater into a normal source repository before relying on it operationally.
