<#
.SYNOPSIS
    Issue a GDAP relationship request for a Sentinel to Defender XDR
    1-Week Migration engagement. One command per customer.

.DESCRIPTION
    Reads the role + duration spec from gdap-relationship-spec.json,
    creates a new GDAP relationship via Microsoft Graph, and prints
    the activation link the delivery coordinator emails to the
    customer's Global Administrator.

    Microsoft Graph requires DELEGATED permissions for GDAP creation
    (app-only client credentials are NOT supported on these endpoints
    as of 2026-06). The script uses interactive sign-in via the
    Microsoft Graph PowerShell SDK; the signed-in user must be the
    Simplicity IT Partner Center primary admin (or have an equivalent
    delegated role).

    The acceptance URL is constructed from the relationship ID per
    Microsoft's documented pattern at
    learn.microsoft.com/en-us/partner-center/customers/gdap-introduction.

.PARAMETER CustomerName
    Display label that appears in Partner Center and the customer's
    Microsoft 365 admin center. Visible to the customer; keep it
    professional. Example: "Sentinel-to-Defender Migration -
    Contoso Pharmaceuticals".

.PARAMETER DurationDays
    Override the relationship duration. Default: read from
    gdap-relationship-spec.json (14 days, per the engagement +
    grace window).

.PARAMETER SpecFile
    Path to the GDAP relationship spec JSON. Default: sibling file
    gdap-relationship-spec.json shipped in this folder.

.EXAMPLE
    .\New-GdapRelationship.ps1 -CustomerName "Sentinel-to-Defender Migration - Contoso Pharma"

.EXAMPLE
    # Override the duration to 21 days (longer engagement window)
    .\New-GdapRelationship.ps1 -CustomerName "..." -DurationDays 21

.NOTES
    Copyright Simplicity IT Inc. MIT licensed.
    Asset: assets/gdap-onboarding-template/
    Locked 2026-06-13.
#>

#Requires -Version 7
#Requires -Modules Microsoft.Graph.Identity.Partner

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CustomerName,
    [int]$DurationDays = 0,
    [string]$SpecFile = (Join-Path $PSScriptRoot 'gdap-relationship-spec.json')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SpecFile)) {
    throw "Spec file not found: $SpecFile"
}

$spec = Get-Content $SpecFile -Raw | ConvertFrom-Json

# Resolve duration. Either an explicit -DurationDays param wins, or
# we parse the ISO 8601 duration from the spec (e.g. "P14D" -> 14).
if ($DurationDays -le 0) {
    $isoDuration = $spec.duration
    if ($isoDuration -match '^P(\d+)D$') {
        $DurationDays = [int]$Matches[1]
    } else {
        throw "Could not parse duration '$isoDuration' from spec; pass -DurationDays explicitly."
    }
}

# Role definition IDs from spec.
$roleIds = @($spec.accessDetails.unifiedRoles | ForEach-Object { $_.roleDefinitionId })
if ($roleIds.Count -eq 0) {
    throw "Spec has no unifiedRoles entries; check $SpecFile"
}

Write-Host "Issuing GDAP relationship:" -ForegroundColor Cyan
Write-Host "  CustomerName: $CustomerName"
Write-Host "  Duration:     $DurationDays days"
Write-Host "  Roles:        $($roleIds.Count) ($(($spec.accessDetails.unifiedRoles | ForEach-Object { $_._roleDefinitionName }) -join ', '))"
Write-Host ""

# Sign in to Microsoft Graph with the right scopes.
# DelegatedAdminRelationship.ReadWrite.All is the canonical scope per
# Microsoft Graph docs for creating GDAP relationships.
Write-Host "Signing in to Microsoft Graph (Simplicity IT Partner Center admin required)..." -ForegroundColor Yellow
Connect-MgGraph -Scopes "DelegatedAdminRelationship.ReadWrite.All" -NoWelcome | Out-Null

# Construct the request body.
$durationIso = "P${DurationDays}D"
$body = @{
    displayName    = $CustomerName
    duration       = $durationIso
    accessDetails  = @{
        unifiedRoles = @($roleIds | ForEach-Object {
            @{ roleDefinitionId = $_ }
        })
    }
    autoExtendDuration = "PT0S"
}

# Microsoft Graph endpoint for GDAP relationship creation.
$uri = "https://graph.microsoft.com/v1.0/tenantRelationships/delegatedAdminRelationships"

try {
    $response = Invoke-MgGraphRequest -Method POST -Uri $uri -Body ($body | ConvertTo-Json -Depth 8) -ContentType "application/json"
} catch {
    throw "GDAP relationship creation failed: $($_.Exception.Message)"
}

$relationshipId = $response.id
if (-not $relationshipId) {
    throw "Graph returned no relationship id; raw response: $($response | ConvertTo-Json -Depth 4)"
}

Write-Host "Created relationship $relationshipId" -ForegroundColor Green

# Microsoft's documented acceptance-link shape:
# admin.microsoft.com/AdminPortal/Home#/partners/invitation/granularAdminRelationships/{relationship-id}
$acceptanceUrl = "https://admin.microsoft.com/AdminPortal/Home#/partners/invitation/granularAdminRelationships/$relationshipId"

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Send this acceptance URL to the customer's Global Administrator:" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  $acceptanceUrl" -ForegroundColor White
Write-Host ""
Write-Host "  Relationship status:     created (awaiting customer acceptance)" -ForegroundColor DarkGray
Write-Host "  Relationship duration:   $DurationDays days from acceptance" -ForegroundColor DarkGray
Write-Host "  Roles requested:         $(($spec.accessDetails.unifiedRoles | ForEach-Object { $_._roleDefinitionName }) -join ', ')" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Customer next step: open the URL, sign in as Global Admin,"  -ForegroundColor DarkGray
Write-Host "  review the requested roles, and click Approve."               -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Status check (anytime): " -NoNewline -ForegroundColor DarkGray
Write-Host "Get-MgTenantRelationshipDelegatedAdminRelationship -DelegatedAdminRelationshipId $relationshipId" -ForegroundColor White

# Disconnect Graph session.
Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

# Emit structured object for piping.
[PSCustomObject]@{
    RelationshipId  = $relationshipId
    CustomerName    = $CustomerName
    DurationDays    = $DurationDays
    AcceptanceUrl   = $acceptanceUrl
    RolesRequested  = @($spec.accessDetails.unifiedRoles | ForEach-Object { $_._roleDefinitionName })
    CreatedAt       = (Get-Date -Format o)
}
