<#
.SYNOPSIS
    Workbooks inventory module. Enumerates Sentinel/My Workbooks
    associated with each target workspace, classifies each by
    portability to the unified Defender XDR portal, and emits v2
    schema rows.

.DESCRIPTION
    Closes Day 4 of the engagement methodology. Replaces what was
    previously a manual workbook walkthrough with a scripted pass:
    every workbook gets categorized as:

      - native_template     : maps cleanly to a Defender XDR gallery
                              workbook; no porting required
      - portable_custom     : custom workbook whose KQL is compatible
                              with the unified query language
      - kql_rewrite_required: custom workbook with deprecated tables
                              (SecurityEvent, SigninLogs) that need
                              rewrites to the unified equivalents
      - broken              : workbook references resources that no
                              longer exist (deleted connectors,
                              renamed tables)

    Emits one v2-schema row per workbook. WARNING rows carry the
    remediation action id `workbook.port` (rewrite required) or
    `workbook.recreate` (broken).

.NOTES
    Copyright Simplicity IT Inc. MIT licensed.
    Module: Workbooks Inventory (Day 4 acceleration).
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

$token = Connect-Sentinel -AuthMode $AuthMode -ClientId $ClientId -ClientSecret $ClientSecret -TenantId $TenantId
$envs  = Read-Environments -EnvironmentsFile $EnvironmentsFile
$headers = @{ Authorization = "Bearer $token" }

# Deprecated table names that signal a unified-portal rewrite.
$deprecatedTables = @(
    'SecurityEvent',          # -> DeviceLogonEvents, DeviceProcessEvents
    'SigninLogs',             # -> IdentityLogonEvents
    'AuditLogs',              # -> review tenant-side
    'OfficeActivity',         # -> CloudAppEvents
    'AzureNetworkAnalytics_CL'
)

foreach ($e in $envs) {
    Write-Host "[Workbooks] $($e.workspaceName)" -ForegroundColor Cyan

    # Enumerate workbooks via the Workbooks REST API. category=sentinel
    # filters to Sentinel-authored workbooks; null returns all.
    $apiVersion = '2024-09-01'
    $uri = "https://management.azure.com/subscriptions/$($e.subscriptionId)/resourceGroups/$($e.resourceGroupName)/providers/Microsoft.Insights/workbooks?category=sentinel&api-version=$apiVersion"

    try {
        $resp = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ErrorAction Stop
    } catch {
        Write-Warning "Failed to list workbooks for $($e.workspaceName): $($_.Exception.Message)"
        Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
            -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
            -Section 'Workbooks' -Status 'WARNING' `
            -Message "Could not enumerate workbooks: $($_.Exception.Message)" `
            -CurrentValue 'enumeration failed' `
            -ExpectedValue 'enumeration succeeds with Microsoft Sentinel Reader role' `
            -SeverityRationale 'Unable to assess workbook portability; manual review required.' `
            -RemediationActionId 'manual.review'
        continue
    }

    $workbooks = @($resp.value)
    if ($workbooks.Count -eq 0) {
        Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
            -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
            -Section 'Workbooks' -Status 'OK' `
            -Message 'No Sentinel workbooks in this workspace; nothing to port.'
        continue
    }

    $passed = 0
    foreach ($wb in $workbooks) {
        $name = $wb.properties.displayName
        $serializedData = $wb.properties.serializedData

        # Classify by content.
        $hasDeprecated = $false
        foreach ($t in $deprecatedTables) {
            if ($serializedData -match "\b$t\b") { $hasDeprecated = $true; break }
        }
        $hasInvalidRef = ($serializedData -match '"resourceTypes":\s*\["microsoft\.operationalinsights/workspaces/dataconnectors"\]')

        if ($hasInvalidRef) {
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Workbooks' -Status 'WARNING' -SubItem $name `
                -Message "Workbook references resource types that don't exist in unified Defender portal; must be recreated" `
                -CurrentValue 'references deprecated resource type microsoft.operationalinsights/workspaces/dataconnectors' `
                -ExpectedValue 'reference Defender XDR-compatible resources only' `
                -SeverityRationale 'Workbook will render empty or error post-onboarding; broken visualization for SOC.' `
                -RemediationActionId 'workbook.recreate'
        }
        elseif ($hasDeprecated) {
            $deprecatedList = ($deprecatedTables | Where-Object { $serializedData -match "\b$_\b" }) -join ', '
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Workbooks' -Status 'WARNING' -SubItem $name `
                -Message "Workbook KQL references deprecated tables; rewrite required for unified portal" `
                -CurrentValue "uses table(s): $deprecatedList" `
                -ExpectedValue 'KQL rewritten to use unified Defender XDR equivalents (DeviceLogonEvents, IdentityLogonEvents, CloudAppEvents, etc.)' `
                -SeverityRationale 'Queries will execute but return empty results in unified portal; SOC visualization regression.' `
                -RemediationActionId 'workbook.port'
        }
        else {
            $passed++
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Workbooks' -Status 'OK' -SubItem $name `
                -Message 'Workbook portable to unified portal without KQL rewrite'
        }
    }

    Add-ResultRow -OutputCsv $OutputCsv -Append:$Append -Type 'score' `
        -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
        -Section 'Workbooks' -Passed $passed -Total $workbooks.Count `
        -Percent ([math]::Round(($passed / $workbooks.Count) * 100, 2))
}

Write-Host "[Workbooks] done." -ForegroundColor Green
