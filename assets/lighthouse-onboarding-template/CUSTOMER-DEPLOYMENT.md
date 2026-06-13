# Lighthouse Onboarding: Customer Deployment Guide

This one-pager explains how to deploy the Azure Lighthouse delegation
that the **Sentinel to Defender XDR 1-Week Migration** engagement
uses for delegated access to your Microsoft Sentinel workspace.

You run this **once**, before the engagement kicks off. Removal
happens on Day 7 as a deliverable line item.

## What it does

Creates a Lighthouse registration in your subscription that grants
the Simplicity IT Inc. Sentinel Delivery team three role assignments
on the Sentinel resources only:

| Role | Scope | Why |
|---|---|---|
| Microsoft Sentinel Contributor | Workspace | Run the assessment, generate the readiness report, execute Day 3 remediation actions, perform the Day 6 cutover |
| Logic App Contributor | Sentinel resource group | Port and rebuild playbooks on Day 5 |
| Reader | Subscription | Inspect connector dependencies; never used for writes |

No standing credentials. No shared accounts. No service principals
created in your tenant. Lighthouse is the Microsoft-supported
pattern for delegated partner access.

Microsoft Defender XDR Security Administrator is **not** included
in this template (Lighthouse delegates Azure RBAC; Defender XDR is
a Microsoft 365 surface). For the Day 6 cutover, that role is
granted separately via your privileged-access policy and revoked at
the end of the cutover window.

## What it does NOT do

- Grant access to anything outside the Sentinel workspace and
  resource group
- Grant access to data outside Microsoft Sentinel (no email, no
  files, no identities)
- Create persistent service principals in your tenant
- Auto-expire (Lighthouse has no time-bound contract; **you remove
  the delegation on Day 7** as a documented Day 7 deliverable)

## Pre-requisites

- Azure subscription that hosts your Microsoft Sentinel workspace
- Global Administrator OR Owner on that subscription
- Five minutes

## Step-by-step (Azure portal)

1. Sign in to https://portal.azure.com as Global Admin or Owner.
2. Open **Subscriptions** in the top search bar; pick the
   subscription that hosts your Microsoft Sentinel workspace.
3. In the left blade, expand **Settings** and click **Deployments**.
4. Click **+ Create** → **Template deployment (deploy using custom
   templates)**.
5. Click **Build your own template in the editor**, then click
   **Load file** and select `lighthouseDelegation.json` from the
   files Simplicity IT shared with you.
6. Click **Save**.
7. On the parameters screen, the `managedByTenantId` and
   `authorizations` values are pre-filled by Simplicity IT (you
   should see "Simplicity IT Inc." values, not the
   `<placeholder>` strings). If you see placeholders, **stop and
   contact your engagement lead**; the template wasn't published
   correctly.
8. Click **Review + create**, then **Create**. The deployment
   completes in roughly 30 to 60 seconds.

## Step-by-step (PowerShell, alternative)

```powershell
# Sign in
Connect-AzAccount
Select-AzSubscription -SubscriptionId "<your-subscription-id>"

# Deploy
New-AzDeployment `
  -Name "SimplicityIT-Sentinel-Lighthouse" `
  -Location "<your-preferred-region>" `
  -TemplateFile ".\lighthouseDelegation.json" `
  -TemplateParameterFile ".\lighthouseDelegation.parameters.json"
```

## Verifying the delegation

In the Azure portal, search for **Service providers** and confirm
the offer **"Sentinel to Defender XDR 1-Week Migration (Simplicity
IT Inc.)"** appears with the three role assignments listed above.

## Removing the delegation on Day 7

The engagement's Day 7 deliverable includes the removal. The Simplicity IT
engineer will walk you through the removal during the Day 7 acceptance
session. You confirm the removal in real time. After Day 7, no
Simplicity IT identity retains access to your tenant.

For your reference, the manual removal path is:

1. Sign in to https://portal.azure.com
2. Search **Service providers**
3. Locate the offer **"Sentinel to Defender XDR 1-Week Migration
   (Simplicity IT Inc.)"**
4. Click the row → **Delete**
5. Confirm. The deletion completes immediately.

## Questions

Contact your engagement lead at sales@simplicityitinc.com or via
the engagement shared Teams channel.
