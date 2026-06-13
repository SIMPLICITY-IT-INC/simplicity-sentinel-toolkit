<#
.SYNOPSIS
    Playbook (Logic Apps) inventory module. Enumerates Sentinel-
    connected Logic Apps in each workspace's resource group, walks
    each playbook's trigger + connectors, and classifies for the
    Day 5 rebuild phase.

.DESCRIPTION
    Closes Day 5 of the engagement methodology. Categorizes each
    playbook:

      - portable_native    : trigger is Sentinel-native and survives
                             onboarding; connectors all on the
                             accepted list
      - reauth_required    : playbook works but external connectors
                             (ServiceNow, Jira, Teams) need
                             credential refresh in the unified portal
      - trigger_rewrite    : playbook trigger uses an Incident
                             property that is removed or renamed post-
                             onboarding (Incident Title, Incident
                             Provider, Description)
      - broken             : playbook references a Sentinel resource
                             that no longer exists, or its API
                             definition is invalid

.NOTES
    Copyright Simplicity IT Inc. MIT licensed.
    Module: Playbook Inventory (Day 5 acceleration).
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

# External connector providers that require credential reauth in the
# unified portal (the OAuth/API key needs to be re-established in the
# new connection context).
$reauthConnectors = @(
    'servicenow', 'jira', 'salesforce',
    'office365', 'teams', 'outlook',
    'sendgrid', 'twilio'
)

foreach ($e in $envs) {
    Write-Host "[Playbooks] $($e.workspaceName)" -ForegroundColor Cyan

    $apiVersion = '2019-05-01'
    $uri = "https://management.azure.com/subscriptions/$($e.subscriptionId)/resourceGroups/$($e.resourceGroupName)/providers/Microsoft.Logic/workflows?api-version=$apiVersion"

    try {
        $resp = Invoke-RestMethod -Method GET -Uri $uri -Headers $headers -ErrorAction Stop
    } catch {
        Write-Warning "Failed to list Logic Apps for $($e.workspaceName): $($_.Exception.Message)"
        Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
            -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
            -Section 'Playbooks' -Status 'WARNING' `
            -Message "Could not enumerate Logic Apps: $($_.Exception.Message)" `
            -CurrentValue 'enumeration failed' `
            -ExpectedValue 'enumeration succeeds with Logic App Reader role' `
            -SeverityRationale 'Unable to assess playbook portability; manual review required.' `
            -RemediationActionId 'manual.review'
        continue
    }

    $apps = @($resp.value)
    if ($apps.Count -eq 0) {
        Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
            -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
            -Section 'Playbooks' -Status 'OK' `
            -Message 'No Logic Apps in this resource group; nothing to rebuild.'
        continue
    }

    $passed = 0
    foreach ($app in $apps) {
        $name = $app.name
        $definitionUri = "https://management.azure.com$($app.id)?api-version=$apiVersion&%24expand=definition,parameters"
        try {
            $detail = Invoke-RestMethod -Method GET -Uri $definitionUri -Headers $headers -ErrorAction Stop
        } catch {
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Playbooks' -Status 'WARNING' -SubItem $name `
                -Message "Could not fetch playbook definition; broken or missing permissions" `
                -CurrentValue 'definition fetch failed' `
                -ExpectedValue 'fetched JSON definition' `
                -SeverityRationale "Playbook cannot be inspected programmatically; treat as broken pending manual review." `
                -RemediationActionId 'manual.review'
            continue
        }

        # Look for Sentinel trigger.
        $triggerJson = $detail.properties.definition.triggers | ConvertTo-Json -Depth 8 -Compress
        $hasSentinelTrigger = ($triggerJson -match 'azuresentinel|microsoftsentinel|securityinsights')

        # Look for problematic trigger condition properties.
        $hasTitleCondition = ($triggerJson -match '"Title"' -or $triggerJson -match 'IncidentTitle')
        $hasProviderCondition = ($triggerJson -match '"Provider"' -or $triggerJson -match 'IncidentProvider')
        $hasDescriptionCondition = ($triggerJson -match '"Description"' -and -not ($triggerJson -match '"@triggerBody'))

        # Look for external connector references.
        $allActionsJson = ($detail.properties.definition.actions | ConvertTo-Json -Depth 12 -Compress).ToLower()
        $reauthList = @()
        foreach ($c in $reauthConnectors) {
            if ($allActionsJson -match "/$c|`"$c`"") { $reauthList += $c }
        }

        # Classify in priority order.
        if (-not $hasSentinelTrigger) {
            $passed++
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Playbooks' -Status 'INFORMATIONAL' -SubItem $name `
                -Message 'Not a Sentinel-triggered playbook; no migration impact'
        }
        elseif ($hasTitleCondition) {
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Playbooks' -Status 'WARNING' -SubItem $name `
                -Message 'Trigger conditions on Incident Title; Defender XDR may rename incidents at correlation' `
                -CurrentValue 'trigger keyed on IncidentTitle' `
                -ExpectedValue 'trigger keyed on Analytics Rule Name or Analytics Rule IDs' `
                -SeverityRationale 'Title-based matching will silently stop firing once XDR correlation renames incidents.' `
                -RemediationActionId 'automation.trigger.title-rewrite'
        }
        elseif ($hasProviderCondition) {
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Playbooks' -Status 'WARNING' -SubItem $name `
                -Message 'Trigger conditions on Incident Provider; property is removed post-onboarding' `
                -CurrentValue 'trigger keyed on IncidentProvider property' `
                -ExpectedValue 'condition removed or rewritten to AlertProductName' `
                -SeverityRationale 'Provider Name becomes "Microsoft XDR" universally; condition stops discriminating.' `
                -RemediationActionId 'automation.condition.provider-remove'
        }
        elseif ($hasDescriptionCondition) {
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Playbooks' -Status 'WARNING' -SubItem $name `
                -Message 'Conditions reference Incident Description; field is removed post-onboarding' `
                -CurrentValue 'logic reads Incident.Description' `
                -ExpectedValue 'redesigned on a surviving property (RelatedAnalyticRuleIds, Severity, Tactics)' `
                -SeverityRationale 'Description field is removed; condition silently stops matching.' `
                -RemediationActionId 'automation.condition.description-redesign'
        }
        elseif ($reauthList.Count -gt 0) {
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Playbooks' -Status 'INFORMATIONAL' -SubItem $name `
                -Message "External connector(s) need credential reauth post-onboarding: $($reauthList -join ', ')" `
                -CurrentValue "uses external connector(s): $($reauthList -join ', ')" `
                -ExpectedValue 'connector credentials re-established in unified portal' `
                -SeverityRationale 'Playbook port is mechanical but the external auth must be re-established once.' `
                -RemediationActionId 'playbook.reauth'
        }
        else {
            $passed++
            Add-ResultRow -OutputCsv $OutputCsv -Append:$Append `
                -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
                -Section 'Playbooks' -Status 'OK' -SubItem $name `
                -Message 'Playbook portable as-is; no rewrite or reauth required'
        }
    }

    Add-ResultRow -OutputCsv $OutputCsv -Append:$Append -Type 'score' `
        -Environment $e.workspaceName -ResourceGroup $e.resourceGroupName -SubscriptionId $e.subscriptionId `
        -Section 'Playbooks' -Passed $passed -Total $apps.Count `
        -Percent ([math]::Round(($passed / $apps.Count) * 100, 2))
}

Write-Host "[Playbooks] done." -ForegroundColor Green
