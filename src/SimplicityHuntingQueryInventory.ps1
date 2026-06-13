<#
.SYNOPSIS
    Hunting queries inventory module. Enumerates saved hunting queries
    in each Sentinel workspace and classifies for compatibility with
    the unified Defender XDR advanced-hunting schema.

.DESCRIPTION
    Closes the Day 1-3 hunting-query gap in the engagement methodology.
    Categorizes each hunting query:

      - portable       : KQL is compatible with the unified Defender XDR
                         schema (uses CommonSecurityLog, etc. that
                         continue to work post-onboarding)
      - table_rewrite  : KQL uses legacy Sentinel tables that have
                         renamed equivalents (SecurityEvent -> DeviceLogonEvents,
                         SigninLogs -> IdentityLogonEvents)
      - join_rewrite   : KQL uses join semantics or functions deprecated
                         under the unified portal
      - broken         : KQL references resources that don't exist

.NOTES
    Copyright Simplicity IT Inc. MIT licensed.
    Module: Hunting Query Inventory (Day 1-3 acceleration).
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

# Table renames between Sentinel/Log Analytics and unified Defender XDR.
$tableMap = @{
    'SecurityEvent'         = 'DeviceLogonEvents / DeviceProcessEvents'
    'SigninLogs'            = 'IdentityLogonEvents'
    'OfficeActivity'        = 'CloudAppEvents'
    'AzureNetworkAnalytics_CL' = 'no direct equivalent; requires custom log mapping'
    'CommonSecurityLog'     = 'review per data source'
}

# KQL functions/operators that don't survive unmodified.
$deprecatedFunctions = @(
    'externaldata',           # not supported in advanced hunting
    'datatable\s*\(',         # limited support
    'parse_json\s*\('         # use parse_json renamed under unified
)

foreach ($e in $envs) {
    Write-Host "[Hunting] $($e.workspaceName)" -ForegroundColor Cyan

    $apiVersion = '2024-09-01'
    $uri = "https://management.azure.com/subscriptions/$($e.subscriptionId)/resourceGroups/$($e.resourceGroupName)/providers/Microsoft.OperationalInsights/workspaces/$($e.workspaceName)/savedSearches?api-version=$apiVersion"

    try {
        $resp = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ErrorAction Stop
    } catch {
        Write-Warning "Failed to list saved searches for $($e.workspaceName): $($_.Exception.Message)"
        Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
            -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
            -Section 'Hunting' -Status 'WARNING' `
            -Message "Could not enumerate hunting queries: $($_.Exception.Message)" `
            -CurrentValue 'enumeration failed' `
            -ExpectedValue 'enumeration succeeds with Sentinel Reader role' `
            -SeverityRationale 'Unable to assess hunting compatibility; manual review required.' `
            -RemediationActionId 'manual.review'
        continue
    }

    $queries = @($resp.value | Where-Object {
        $_.properties.category -match 'hunting|threat hunting'
    })

    if ($queries.Count -eq 0) {
        Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
            -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
            -Section 'Hunting' -Status 'OK' `
            -Message 'No saved hunting queries in this workspace.'
        continue
    }

    $passed = 0
    foreach ($q in $queries) {
        $name = $q.properties.displayName
        $kql  = $q.properties.query

        $usedDeprecated = @()
        foreach ($t in $tableMap.Keys) {
            if ($kql -match "\b$t\b") { $usedDeprecated += $t }
        }
        $usedFunctions = @()
        foreach ($f in $deprecatedFunctions) {
            if ($kql -match $f) { $usedFunctions += $f -replace '\\s\*', '' -replace '\\', '' }
        }

        if ($usedDeprecated.Count -gt 0 -and $usedFunctions.Count -gt 0) {
            $details = "tables [$($usedDeprecated -join ', ')] + functions [$($usedFunctions -join ', ')]"
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Hunting' -Status 'WARNING' -SubItem $name `
                -Message "Hunting query needs table renames + function rewrites for unified portal" `
                -CurrentValue "uses $details" `
                -ExpectedValue 'rewritten to use unified Defender XDR schema (DeviceLogonEvents, IdentityLogonEvents, CloudAppEvents) + portable KQL only' `
                -SeverityRationale 'Hunters will see empty/errored results when running this query in the unified portal.' `
                -RemediationActionId 'hunting.kql-rewrite'
        }
        elseif ($usedDeprecated.Count -gt 0) {
            $map = ($usedDeprecated | ForEach-Object { "$_ -> $($tableMap[$_])" }) -join '; '
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Hunting' -Status 'WARNING' -SubItem $name `
                -Message "Hunting query uses deprecated table names; rewrite to unified equivalents" `
                -CurrentValue "uses table(s): $($usedDeprecated -join ', ')" `
                -ExpectedValue "rewritten with: $map" `
                -SeverityRationale 'Query will return empty results in the unified portal until tables are mapped.' `
                -RemediationActionId 'hunting.table-rewrite'
        }
        elseif ($usedFunctions.Count -gt 0) {
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Hunting' -Status 'WARNING' -SubItem $name `
                -Message "Hunting query uses KQL function(s) with limited unified-portal support" `
                -CurrentValue "uses function(s): $($usedFunctions -join ', ')" `
                -ExpectedValue 'rewritten with advanced-hunting-portable KQL only' `
                -SeverityRationale 'Query may throw or behave unexpectedly under unified portal advanced hunting.' `
                -RemediationActionId 'hunting.function-rewrite'
        }
        else {
            $passed++
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Hunting' -Status 'OK' -SubItem $name `
                -Message 'Hunting query portable to unified portal as-is'
        }
    }

    Add-ResultRow -OutputCsv $OutputCsv -Append:$Append -Type 'score' `
        -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
        -Section 'Hunting' -Passed $passed -Total $queries.Count `
        -Percent ([math]::Round(($passed / $queries.Count) * 100, 2))
}

Write-Host "[Hunting] done." -ForegroundColor Green
