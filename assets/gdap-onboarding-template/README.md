# GDAP Onboarding Template

Granular Delegated Admin Privileges (GDAP) onboarding asset for the
**Sentinel to Defender XDR 1-Week Migration** consulting engagement.
Implements Path A's GDAP half per `IMPLEMENTATION-GUIDE.md` §2.1
(locked 2026-06-13 after the Lighthouse-only positioning was found
to under-cover the Defender XDR surface).

**Why GDAP alongside Lighthouse:** the Defender XDR portal (the
post-migration surface customers move to) uses Unified RBAC and
draws Entra ID roles via GDAP, not Azure RBAC via Lighthouse. The
engagement needs both for end-to-end coverage. See
`learn.microsoft.com/azure/defender-for-cloud/defender-portal/integration-faq`
for Microsoft's own statement of the dual-permission requirement.

## Files

| File | Purpose |
|---|---|
| `gdap-relationship-spec.json` | Role list + duration + JIT note; the spec the partner uses to fill in the Partner Center New GDAP Request form, and the source-of-truth record for the engagement scoping notes |
| `New-GdapRelationship.ps1` | One-command GDAP relationship issuance via Microsoft Graph. Reads the spec, prompts for the Simplicity IT Partner Center admin sign-in, prints the acceptance URL for the customer's Global Administrator. Requires `Microsoft.Graph.Identity.Partner` PowerShell module |
| `CUSTOMER-DEPLOYMENT.md` | One-pager for the customer's Global Administrator to follow when accepting the GDAP relationship |
| `README.md` | This file |

## Quick start (per customer engagement)

```powershell
# 1. From the delivery team's terminal:
Install-Module Microsoft.Graph.Identity.Partner -Scope CurrentUser  # one-time
cd assets/gdap-onboarding-template
.\New-GdapRelationship.ps1 -CustomerName "Sentinel-to-Defender Migration - <CustomerLegalName>"

# 2. Email the printed acceptance URL to the customer's Global Admin
#    (with CUSTOMER-DEPLOYMENT.md attached as the step-by-step).
# 3. Customer accepts; verify status from your terminal:
Connect-MgGraph -Scopes "DelegatedAdminRelationship.Read.All"
Get-MgTenantRelationshipDelegatedAdminRelationship -DelegatedAdminRelationshipId <id-from-step-1>
```

## For the Simplicity IT delivery team

Before sharing the customer one-pager with a customer, confirm:

1. Your Partner Center publisher account is configured under the
   Microsoft Partner Network for the customer's geography.
2. The customer is reachable via the indirect or direct CSP
   relationship path your Partner Center uses.
3. The Microsoft Entra role template IDs in `gdap-relationship-spec.json`
   are the current Microsoft-published IDs:
   - Security Administrator: `194ae4cb-b126-40b2-bd5b-6091b380977d`
   - Security Operator: `5f2222b1-57c3-48ba-8ad5-d4759f1fde6f`
   - Cloud Application Administrator: `158c047a-c907-4556-b7ef-446551a6b5f7`
4. Your Simplicity IT Sentinel Delivery security group is provisioned
   in your tenant and the delivery engineers are members.

If the customer requires JIT eligibility (regulated buyer pattern):

- Confirm with the customer that they have Microsoft Entra ID P2
  (included in M365 E5; standalone purchase otherwise).
- Walk them through the My Access portal configuration in the
  CUSTOMER-DEPLOYMENT step 6.
- Schedule a 15-minute Day 0 working session to test a JIT request
  end-to-end so it doesn't block Day 1 work.

## Programmatic creation (optional)

For partners doing many engagements per quarter, the Partner Center
API supports programmatic GDAP relationship creation:

```
POST https://api.partnercenter.microsoft.com/v1/customers/{customerTenantId}/delegatedAdminRelationships
Authorization: Bearer {partner-center-token}
Content-Type: application/json

{
  "displayName": "Simplicity IT - Sentinel to Defender XDR Migration",
  "duration": "P14D",
  "accessDetails": {
    "unifiedRoles": [
      {"roleDefinitionId": "194ae4cb-b126-40b2-bd5b-6091b380977d"},
      {"roleDefinitionId": "5f2222b1-57c3-48ba-8ad5-d4759f1fde6f"},
      {"roleDefinitionId": "158c047a-c907-4556-b7ef-446551a6b5f7"}
    ]
  }
}
```

This is the API call our internal automation in the delivery repo
makes when the engagement coordinator triggers Day 0 onboarding.

## Microsoft Defender XDR scope

GDAP is the documented partner-access path for Defender XDR. Per
Microsoft's GDAP supported-workloads doc
(`learn.microsoft.com/partner-center/customers/gdap-supported-workloads`),
the Security Administrator + Security Operator role combo gives the
delivery team:

- Incidents and alerts (read + manage)
- Advanced Hunting (read + run queries)
- Action Center (read + take actions)
- Threat Analytics (read)
- Defender for Endpoint, Identity, Cloud Apps (managed via the
  unified portal)

If the customer also wants us managed in the M365 Lighthouse partner
portal during the engagement (some MSSP-style customers expect
this), GDAP is a prerequisite per
`learn.microsoft.com/microsoft-365/lighthouse/m365-lighthouse-setup-gdap`.

## What this asset does NOT cover

- Azure RBAC scope (Sentinel workspace, Logic Apps): see
  `../lighthouse-onboarding-template/`.
- Azure Government / sovereign cloud customers: GDAP availability
  in Azure Government is on a separate track; check current parity
  before scoping a GovCloud engagement and default to Path C if
  uncertain.

## Test plan before first customer use

1. Issue a GDAP invitation from the Simplicity IT Partner Center to
   the SIT lab tenant
2. Confirm the lab tenant Global Admin receives the invitation email
3. Accept the relationship in the lab tenant
4. Confirm the Microsoft 365 admin center > Partner relationships
   blade lists the relationship with the three roles
5. Sign in to the Defender portal as a delegated engineer and
   confirm Defender XDR navigation is accessible
6. Test the JIT request flow if configured
7. Tear down per the customer one-pager
8. Confirm the delivery engineer loses access immediately

Record elapsed minutes for steps 1 and 7 in the engagement scoping
notes (used to honor the SOW commitment of "customer can accept in
under 5 minutes").
