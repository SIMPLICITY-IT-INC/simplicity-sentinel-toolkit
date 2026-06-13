# Lighthouse Onboarding Template

Azure Lighthouse delegation asset for the **Sentinel to Defender XDR
1-Week Migration** consulting engagement. Implements Path A (the
preferred access posture) of `IMPLEMENTATION-GUIDE.md` §2.1.

## Files

| File | Purpose |
|---|---|
| `lighthouseDelegation.json` | ARM template defining the registration definition + assignment |
| `lighthouseDelegation.parameters.json` | Parameter file the customer deploys with |
| `CUSTOMER-DEPLOYMENT.md` | One-pager the customer's Global Admin follows |
| `README.md` | This file |

## For the Simplicity IT delivery team

Before sharing the template with a customer, replace the three
`<placeholder>` strings in `lighthouseDelegation.parameters.json`:

- `managedByTenantId` -> Simplicity IT Inc. Entra tenant ID (the
  production tenant; not the lab)
- `principalId` (3 occurrences) -> object ID of the Simplicity IT
  Sentinel Delivery security group in the Simplicity IT tenant

These values are environment-specific and live in the team's
configuration vault, not in this repo.

The built-in role IDs hard-coded in `authorizations` are Azure
well-known IDs:

- `ab8e14d6-4a74-4a29-9ba8-549422addade` = Microsoft Sentinel
  Contributor
- `87a39d53-fc1b-424a-814c-f7e04687dc9e` = Logic App Contributor
- `acdd72a7-3385-48ef-bd42-f606fba81ae7` = Reader

These are stable Microsoft-published IDs; do not change them.

## Test plan before first customer use

1. Deploy into the Simplicity IT lab tenant as the "customer"
   subscription
2. Confirm the Service Providers blade lists the offer
3. Confirm the delivery team can run `Get-AzSentinel` against the
   lab workspace
4. Tear down per the customer-facing one-pager
5. Confirm the delivery team loses access immediately

Record the elapsed time for steps 1 and 4 in the engagement scoping
notes (used to honor the SOW commitment of "customer can deploy in
under 5 minutes").

## Microsoft Defender XDR Security Administrator

Lighthouse delegates Azure RBAC only. Microsoft Defender XDR is a
Microsoft 365 surface; the Defender XDR Security Administrator role
is granted separately during the cutover window via the customer's
privileged-access policy and revoked at the end of Day 6.
