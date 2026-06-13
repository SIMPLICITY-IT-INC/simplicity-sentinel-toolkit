# Shared row-emit helper for the standalone Simplicity IT extension modules.
#
# The orchestrator (Run-FullAssessment.ps1) invokes each extension module
# as a separate child PowerShell process with -OutputCsv pointing at the
# combined results.csv. Each module dot-sources this file to get a
# uniform Add-ResultRow function that emits the v2 16-column schema:
#
#   Type, Environment, ResourceGroup, SubscriptionId, Section, Status,
#   Passed, Total, Percent, Message, SubItem, FindingId, CurrentValue,
#   ExpectedValue, SeverityRationale, RemediationActionId
#
# The schema matches DefenderAdoptionHelper.ps1 v2 exactly. Modules that
# emit rows in this shape can be loaded by dashboard.html + Augment-
# Results.ps1 without any orchestrator-side merge logic.
#
# Locked 2026-06-13. Copyright Simplicity IT Inc.

function New-StandaloneFindingId {
    param([string]$Section, [string]$SubItem, [string]$Environment)
    $input = "$Section|$SubItem|$Environment"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($input))
    $sha.Dispose()
    ([System.BitConverter]::ToString($bytes) -replace '-', '').Substring(0, 12).ToLowerInvariant()
}

function Add-ResultRow {
    param(
        [Parameter(Mandatory = $true)][string]$OutputCsv,
        [Parameter(Mandatory = $true)][switch]$Append,
        [string]$Type = 'check',
        [string]$Environment,
        [string]$ResourceGroup = '',
        [string]$SubscriptionId = '',
        [string]$Section = '',
        [string]$Status = '',
        [int]$Passed = 0,
        [int]$Total = 0,
        [double]$Percent = 0,
        [string]$Message = '',
        [string]$SubItem = '',
        [string]$CurrentValue = '',
        [string]$ExpectedValue = '',
        [string]$SeverityRationale = '',
        [string]$RemediationActionId = ''
    )
    $findingId = if ($Type -eq 'check') {
        New-StandaloneFindingId -Section $Section -SubItem $SubItem -Environment $Environment
    } else { '' }

    $row = [PSCustomObject]@{
        Type                = $Type
        Environment         = $Environment
        ResourceGroup       = $ResourceGroup
        SubscriptionId      = $SubscriptionId
        Section             = $Section
        Status              = $Status
        Passed              = $Passed
        Total               = $Total
        Percent             = $Percent
        Message             = $Message
        SubItem             = $SubItem
        FindingId           = $findingId
        CurrentValue        = $CurrentValue
        ExpectedValue       = $ExpectedValue
        SeverityRationale   = $SeverityRationale
        RemediationActionId = $RemediationActionId
    }

    # If the CSV exists, append without re-emitting the header.
    # If it doesn't yet, write the header.
    if ((Test-Path $OutputCsv) -and (Get-Item $OutputCsv).Length -gt 0) {
        $row | Export-Csv -Path $OutputCsv -Append -NoTypeInformation -Encoding UTF8
    } else {
        $row | Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8
    }
}

function Connect-Sentinel {
    param(
        [string]$AuthMode = 'User',
        [string]$ClientId,
        [SecureString]$ClientSecret,
        [string]$TenantId
    )
    if ($AuthMode -eq 'App') {
        if (-not ($ClientId -and $ClientSecret -and $TenantId)) {
            throw "App mode requires ClientId, ClientSecret, TenantId"
        }
        $cred = New-Object System.Management.Automation.PSCredential($ClientId, $ClientSecret)
        Connect-AzAccount -ServicePrincipal -Credential $cred -TenantId $TenantId | Out-Null
    } else {
        $ctx = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $ctx) { Connect-AzAccount | Out-Null }
    }
    (Get-AzAccessToken -ResourceUrl "https://management.azure.com/").Token
}

function Read-Environments {
    param([Parameter(Mandatory = $true)][string]$EnvironmentsFile)
    if (-not (Test-Path $EnvironmentsFile)) {
        throw "Environments file not found: $EnvironmentsFile"
    }
    return (Get-Content $EnvironmentsFile -Raw | ConvertFrom-Json)
}
