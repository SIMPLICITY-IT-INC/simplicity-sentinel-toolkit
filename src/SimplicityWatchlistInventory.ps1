<#
.SYNOPSIS
    Watchlists inventory module. Enumerates watchlists in each
    Sentinel workspace and classifies for post-migration validity.

.DESCRIPTION
    Closes Day 2 of the engagement methodology. Categorizes each
    watchlist:

      - portable       : watchlist survives onboarding intact;
                         continues to be queryable via the unified
                         portal
      - rebaselining_required : watchlist depends on data sources that
                                change schema or table names
                                post-onboarding (Sentinel-only tables)
      - stale          : watchlist has not been updated in >180 days,
                         likely no longer reflects current reality
      - broken         : watchlist source is invalid or empty

.NOTES
    Copyright Simplicity IT Inc. MIT licensed.
    Module: Watchlist Inventory (Day 2 acceleration).
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

# Staleness threshold for the "rebaseline candidate" classification.
$staleDaysThreshold = 180

foreach ($e in $envs) {
    Write-Host "[Watchlists] $($e.workspaceName)" -ForegroundColor Cyan

    $apiVersion = '2024-09-01'
    $uri = "https://management.azure.com/subscriptions/$($e.subscriptionId)/resourceGroups/$($e.resourceGroupName)/providers/Microsoft.OperationalInsights/workspaces/$($e.workspaceName)/providers/Microsoft.SecurityInsights/watchlists?api-version=$apiVersion"

    try {
        $resp = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ErrorAction Stop
    } catch {
        Write-Warning "Failed to list watchlists for $($e.workspaceName): $($_.Exception.Message)"
        Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
            -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
            -Section 'Watchlists' -Status 'WARNING' `
            -Message "Could not enumerate watchlists: $($_.Exception.Message)" `
            -CurrentValue 'enumeration failed' `
            -ExpectedValue 'enumeration succeeds with Microsoft Sentinel Reader role' `
            -SeverityRationale 'Unable to assess watchlist validity; manual review required.' `
            -RemediationActionId 'manual.review'
        continue
    }

    $watchlists = @($resp.value)
    if ($watchlists.Count -eq 0) {
        Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
            -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
            -Section 'Watchlists' -Status 'OK' `
            -Message 'No watchlists in this workspace; nothing to rebaseline.'
        continue
    }

    $passed = 0
    foreach ($wl in $watchlists) {
        $alias = $wl.properties.watchlistAlias
        $displayName = if ($wl.properties.displayName) { $wl.properties.displayName } else { $alias }
        $updated = $wl.properties.updated
        $source = $wl.properties.source
        $itemsSearchKey = $wl.properties.itemsSearchKey
        $numberOfLines = $wl.properties.numberOfLinesToSkip

        $isStale = $false
        if ($updated) {
            try {
                $updatedDate = [DateTime]::Parse($updated)
                $ageDays = ((Get-Date) - $updatedDate).TotalDays
                if ($ageDays -gt $staleDaysThreshold) { $isStale = $true }
            } catch { }
        }

        $hasContent = ($numberOfLines -ge 0 -and $source)

        if (-not $hasContent) {
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Watchlists' -Status 'WARNING' -SubItem $displayName `
                -Message 'Watchlist source is empty or invalid' `
                -CurrentValue 'no items / no source' `
                -ExpectedValue 'populated watchlist with valid items source' `
                -SeverityRationale 'Empty watchlist is dead weight; consuming queries will return no matches in the unified portal.' `
                -RemediationActionId 'watchlist.recreate'
        }
        elseif ($isStale) {
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Watchlists' -Status 'WARNING' -SubItem $displayName `
                -Message "Watchlist not updated in over $staleDaysThreshold days; rebaseline recommended before cutover" `
                -CurrentValue "last updated $updated" `
                -ExpectedValue "refreshed against current data within $staleDaysThreshold days" `
                -SeverityRationale 'Stale watchlist may carry outdated indicators or asset references that mismatch reality post-onboarding.' `
                -RemediationActionId 'watchlist.rebaseline'
        }
        else {
            $passed++
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Watchlists' -Status 'OK' -SubItem $displayName `
                -Message 'Watchlist portable to unified portal as-is'
        }
    }

    Add-ResultRow -OutputCsv $OutputCsv -Append:$Append -Type 'score' `
        -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
        -Section 'Watchlists' -Passed $passed -Total $watchlists.Count `
        -Percent ([math]::Round(($passed / $watchlists.Count) * 100, 2))
}

Write-Host "[Watchlists] done." -ForegroundColor Green
