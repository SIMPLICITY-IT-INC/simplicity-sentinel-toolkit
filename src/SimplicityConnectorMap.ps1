<#
.SYNOPSIS
    Enumerate Microsoft Sentinel data connectors and map each to its
    Microsoft Defender XDR equivalent. Flag connectors that have no
    Defender XDR equivalent (these stay in Log Analytics only post-
    migration).

.DESCRIPTION
    Pulls the data connector list from each configured workspace via
    the Sentinel REST API, joins each connector against the
    equivalence map in config/defenderXdrEquivalenceMap.json, and
    writes one CSV row per connector with the migration path.

    Module 7 of 8 in the Simplicity IT Sentinel to Defender XDR
    Migration Toolkit orchestrator.

.PARAMETER EnvironmentsFile
    Path to the sentinelEnvironments.json config.

.PARAMETER AuthMode
    User (interactive) or App (service principal).

.PARAMETER ClientId
    App reg client id (required when AuthMode = App).

.PARAMETER ClientSecret
    SecureString (required when AuthMode = App).

.PARAMETER TenantId
    Entra tenant id (required when AuthMode = App).

.PARAMETER OutputCsv
    Path to results.csv. Module appends rows; orchestrator owns the file.

.PARAMETER Append
    Append to OutputCsv instead of overwriting. Default false.

.NOTES
    Copyright Simplicity IT Inc., 2026. Licensed MIT.
    Status: stub. Module shape and CSV row schema are stable; the
    REST API call + equivalence-map join are placeholders pending
    integration testing against a real tenant.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EnvironmentsFile,
    [ValidateSet("User", "App")][string]$AuthMode = "User",
    [string]$ClientId,
    [SecureString]$ClientSecret,
    [string]$TenantId,
    [Parameter(Mandatory = $true)][string]$OutputCsv,
    [switch]$Append
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$mapFile = Join-Path $root "config\defenderXdrEquivalenceMap.json"

# Load equivalence map.
$equivalenceMap = @{}
if (Test-Path $mapFile) {
    $equivalenceMap = Get-Content $mapFile -Raw | ConvertFrom-Json -AsHashtable
} else {
    Write-Warning "Equivalence map not found at $mapFile. Module will mark every connector 'no_mapping_available'."
}

# Load environments.
$environments = Get-Content $EnvironmentsFile -Raw | ConvertFrom-Json

# Output rows accumulate here and get written at the end.
$rows = New-Object System.Collections.Generic.List[psobject]

foreach ($env in $environments) {
    $subscriptionId = $env.subscriptionId
    $resourceGroup  = $env.resourceGroup
    $workspaceName  = $env.workspaceName

    Write-Host "  Workspace: $workspaceName ($subscriptionId/$resourceGroup)"

    # Authenticate per environment if needed.
    # NOTE: real implementation invokes Connect-AzAccount /
    # Get-AzAccessToken here; placeholder for the integration test
    # phase.

    $apiVersion = "2023-02-01-preview"
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/dataConnectors?api-version=$apiVersion"

    try {
        # Placeholder for the actual call:
        # $response = Invoke-AzRestMethod -Path $uri -Method GET
        # $connectors = ($response.Content | ConvertFrom-Json).value
        # Until the integration-test pass lands, we simulate an empty
        # connector list so the orchestrator wires up cleanly.
        $connectors = @()
    } catch {
        Write-Warning "Failed to enumerate connectors for $workspaceName : $($_.Exception.Message)"
        $connectors = @()
    }

    foreach ($conn in $connectors) {
        $kind = $conn.kind
        $equiv = if ($equivalenceMap.ContainsKey($kind)) {
            $equivalenceMap[$kind]
        } else {
            @{ defenderXdrEquivalent = "no_mapping_available"; migrationPath = "stays_in_log_analytics"; notes = "" }
        }

        $status = if ($equiv.defenderXdrEquivalent -eq "no_mapping_available") {
            "WARNING"
        } elseif ($equiv.migrationPath -eq "automatic") {
            "OK"
        } else {
            "INFORMATIONAL"
        }

        $rows.Add([pscustomobject]@{
            Workspace        = $workspaceName
            SubscriptionId   = $subscriptionId
            CheckCategory    = "ConnectorMap"
            CheckName        = "DefenderXdrEquivalence"
            ItemName         = $conn.name
            ItemKind         = $kind
            Status           = $status
            DefenderXdrEquiv = $equiv.defenderXdrEquivalent
            MigrationPath    = $equiv.migrationPath
            Details          = "Connector kind '$kind' maps to '$($equiv.defenderXdrEquivalent)' via path '$($equiv.migrationPath)'."
            Recommendation   = $equiv.notes
        })
    }
}

# Write or append.
$exists = Test-Path $OutputCsv
if ($Append -and $exists) {
    $rows | Export-Csv -Path $OutputCsv -Append -NoTypeInformation
} else {
    $rows | Export-Csv -Path $OutputCsv -NoTypeInformation
}

Write-Host "  ConnectorMap wrote $($rows.Count) rows."
