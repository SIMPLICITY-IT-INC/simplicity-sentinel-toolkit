<#
.SYNOPSIS
    Connector inventory + Defender XDR equivalence mapping module.
    Enumerates Sentinel data connectors in each workspace, joins
    against the equivalence map in config/defenderXdrEquivalenceMap.json,
    and emits v2 schema rows for each connector with its migration path.

.DESCRIPTION
    Closes Day 2 of the engagement methodology. Categorizes each
    connector:

      - native_xdr      : connector kind has a direct Defender XDR
                          equivalent and migrates automatically at
                          onboarding (Defender for Endpoint, Defender
                          for Office 365, Defender for Identity)
      - stays_in_logana : connector stays in Log Analytics post-
                          onboarding; remains queryable via
                          workspace() in advanced hunting
      - manual_bridge   : connector needs a Logic Apps bridge or
                          custom log mapping to project into the
                          unified portal
      - unmapped        : connector kind has no entry in the
                          equivalence map (likely third-party or new);
                          escalate to manual review

    Replaces the prior placeholder implementation (the 2026-06-12
    fork-plan stub that emitted no rows). Module is now a real Sentinel
    REST API client.

.NOTES
    Copyright Simplicity IT Inc. MIT licensed.
    Module: Connector Map (Day 2 acceleration).
    Locked 2026-06-13.
#>

#Requires -Version 7
#Requires -Modules Az.Accounts

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EnvironmentsFile,
    [ValidateSet('User', 'App')][string]$AuthMode = 'User',
    [string]$ClientId,
    [SecureString]$ClientSecret,
    [string]$TenantId,
    [Parameter(Mandatory = $true)][string]$OutputCsv,
    [switch]$Append
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_AddResult-Standalone.ps1')

$root = Split-Path -Parent $PSScriptRoot
$mapFile = Join-Path $root 'config\defenderXdrEquivalenceMap.json'

$map = @{}
if (Test-Path $mapFile) {
    $map = Get-Content $mapFile -Raw | ConvertFrom-Json -AsHashtable
} else {
    Write-Warning "Equivalence map not found at $mapFile. Every connector will be flagged 'unmapped'."
}

$token = Connect-Sentinel -AuthMode $AuthMode -ClientId $ClientId -ClientSecret $ClientSecret -TenantId $TenantId
$envs  = Read-Environments -EnvironmentsFile $EnvironmentsFile
$headers = @{ Authorization = "Bearer $token" }

foreach ($e in $envs) {
    Write-Host "[ConnectorMap] $($e.workspaceName)" -ForegroundColor Cyan

    $apiVersion = '2024-09-01'
    $uri = "https://management.azure.com/subscriptions/$($e.subscriptionId)/resourceGroups/$($e.resourceGroupName)/providers/Microsoft.OperationalInsights/workspaces/$($e.workspaceName)/providers/Microsoft.SecurityInsights/dataConnectors?api-version=$apiVersion"

    try {
        $resp = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ErrorAction Stop
    } catch {
        Write-Warning "Failed to enumerate connectors for $($e.workspaceName): $($_.Exception.Message)"
        Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
            -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
            -Section 'Connector Map' -Status 'WARNING' `
            -Message "Could not enumerate data connectors: $($_.Exception.Message)" `
            -CurrentValue 'enumeration failed' `
            -ExpectedValue 'enumeration succeeds with Microsoft Sentinel Reader role' `
            -SeverityRationale 'Unable to assess connector portability; manual review required.' `
            -RemediationActionId 'manual.review'
        continue
    }

    $connectors = @($resp.value)
    if ($connectors.Count -eq 0) {
        Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
            -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
            -Section 'Connector Map' -Status 'OK' `
            -Message 'No data connectors configured on this workspace.'
        continue
    }

    $passed = 0
    foreach ($c in $connectors) {
        $name = if ($c.name) { $c.name } else { 'unnamed' }
        $kind = if ($c.kind) { $c.kind } else { 'unknown' }

        $equiv = if ($map.ContainsKey($kind)) { $map[$kind] } else { $null }

        if (-not $equiv) {
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Connector Map' -Status 'WARNING' -SubItem $name `
                -Message "Connector kind '$kind' has no Defender XDR equivalence-map entry; escalate to manual review" `
                -CurrentValue "kind = $kind" `
                -ExpectedValue 'kind present in defenderXdrEquivalenceMap.json' `
                -SeverityRationale 'Unknown connector kind; cannot determine migration path without manual mapping.' `
                -RemediationActionId 'connector.region.review'
            continue
        }

        $defenderXdrEquiv = $equiv.defenderXdrEquivalent
        $migrationPath    = $equiv.migrationPath
        $notes            = if ($equiv.notes) { $equiv.notes } else { '' }

        switch ($migrationPath) {
            'automatic' {
                $passed++
                Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                    -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                    -Section 'Connector Map' -Status 'OK' -SubItem $name `
                    -Message "Connector '$kind' migrates automatically at onboarding to '$defenderXdrEquiv'. $notes"
            }
            'stays_in_log_analytics' {
                Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                    -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                    -Section 'Connector Map' -Status 'INFORMATIONAL' -SubItem $name `
                    -Message "Connector '$kind' stays in Log Analytics; remains queryable via workspace() in unified advanced hunting" `
                    -CurrentValue "kind = $kind, target = $defenderXdrEquiv" `
                    -ExpectedValue 'cross-tenant query path validated post-onboarding' `
                    -SeverityRationale "Customer should know the data lives in Log Analytics, not in the unified portal's native schema. $notes" `
                    -RemediationActionId 'connector.region.review'
            }
            'manual_bridge' {
                Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                    -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                    -Section 'Connector Map' -Status 'WARNING' -SubItem $name `
                    -Message "Connector '$kind' needs a Logic Apps bridge or custom-log mapping to project into the unified portal" `
                    -CurrentValue "kind = $kind, target = $defenderXdrEquiv" `
                    -ExpectedValue 'Logic Apps bridge configured OR custom log table created in unified portal' `
                    -SeverityRationale "Without the bridge, data continues to land in Sentinel/Log Analytics but is invisible to unified-portal incident correlation. $notes" `
                    -RemediationActionId 'connector.region.review'
            }
            default {
                Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                    -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                    -Section 'Connector Map' -Status 'INFORMATIONAL' -SubItem $name `
                    -Message "Connector '$kind' has unrecognized migrationPath '$migrationPath'; flag for review" `
                    -CurrentValue "migrationPath = $migrationPath" `
                    -ExpectedValue 'one of: automatic | stays_in_log_analytics | manual_bridge' `
                    -SeverityRationale 'Connector map entry uses a value outside the documented enum; treat as manual review until clarified.' `
                    -RemediationActionId 'manual.review'
            }
        }
    }

    Add-ResultRow -OutputCsv $OutputCsv -Append:$Append -Type 'score' `
        -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
        -Section 'Connector Map' -Passed $passed -Total $connectors.Count `
        -Percent ([math]::Round(($passed / $connectors.Count) * 100, 2))
}

Write-Host "[ConnectorMap] done." -ForegroundColor Green
