# GDAP Onboarding: Customer Acceptance Guide

This one-pager explains how to accept the **Granular Delegated Admin
Privileges (GDAP)** relationship that the **Sentinel to Defender XDR
1-Week Migration** engagement uses for delegated access to the
Microsoft 365 / Defender XDR side of your tenant.

You accept this **once**, before the engagement kicks off. Removal
happens on Day 7 as a deliverable line item.

GDAP is paired with Azure Lighthouse (separate one-pager) for the
Azure / Sentinel workspace side of the engagement. Both are required
because Lighthouse only delegates Azure RBAC and the Defender portal
uses a separate permission model (Unified RBAC).

## What it does

Simplicity IT will send you a GDAP relationship invitation through
the Partner Center customer-engagement flow. Once you accept, our
delivery team can use **time-boxed, role-scoped** Microsoft Entra
ID roles in your tenant:

| Role | Scope | Why |
|---|---|---|
| Security Administrator | Microsoft Entra ID directory | Day 6 cutover "Connect workspace" click in the Defender portal; analytics rule enable/disable in the unified portal |
| Security Operator | Microsoft Entra ID directory | Day 1 read-only Defender XDR surface inventory; Day 6 parity validation; Day 7 handover walkthrough |
| Cloud Application Administrator | Microsoft Entra ID directory | Day 5 Logic Apps playbook port: re-authorize external SOAR connectors (ServiceNow, Jira, Teams) in the unified portal |

**Duration**: 14 days from acceptance. The relationship auto-expires
at the end of the window. Day 7 access teardown is performed in
front of you regardless.

**JIT (just-in-time) activation**: If you have Microsoft Entra ID P2
(included in M365 E5), the roles can be configured as JIT-eligible.
Our engineers must request activation via the My Access portal each
time they need to use a role, and your designated approver reviews
the request. Standing role activation is NOT used unless you choose
to skip JIT.

## What it does NOT do

- Grant access to anything outside the three roles listed above.
- Grant Azure RBAC roles (that's the Lighthouse asset's job).
- Persist beyond the 14-day window (auto-expiring delegation).
- Allow our engineers to read your email, files, or non-security
  M365 data.
- Affect existing role assignments inside your tenant.

## Pre-requisites

- Microsoft 365 tenant with a Global Administrator
- Indirect or direct CSP relationship with Microsoft (not required,
  but typical for managed customers)
- Five minutes

## Step-by-step (Partner Center invitation acceptance)

1. Simplicity IT initiates the GDAP relationship from our Partner
   Center: **Customers > [Your customer name] > Granular delegated
   admin privileges > New request**. We attach the role list from
   the engagement spec and send you the acceptance URL via your
   engagement contact.
2. The acceptance email arrives in your Global Administrator's
   inbox from `microsoft-noreply@microsoft.com`. Subject:
   "[Simplicity IT] Granular delegated admin privileges request".
3. Click the **Accept GDAP relationship** link in the email. You
   are taken to the Microsoft 365 admin center.
4. Sign in as Global Administrator.
5. Review the requested roles (the three listed above). The portal
   shows the role names plus the requested duration. Confirm the
   list matches what Simplicity IT shared during scoping.
6. **(Optional but recommended for regulated buyers):** click
   **Manage approval requests** to configure JIT eligibility.
   Designate a JIT-approver security group from your existing PIM
   policy.
7. Click **Approve and create security groups**. Microsoft 365
   provisions a security group in your tenant for each role; our
   delivery engineers will be added to those groups.

## Verifying the relationship

In your Microsoft 365 admin center, navigate to **Settings > Partner
relationships**. The Simplicity IT relationship appears with the
expiration date and the role list. Sign in to the Defender portal as
a test; you should NOT yet see the Defender XDR navigation as
Simplicity IT (until our engineer signs in with their delegated
context and activates the JIT role if configured).

## Removing the relationship on Day 7

The engagement's Day 7 deliverable includes the removal. The
Simplicity IT engineer walks you through it during the Day 7
acceptance session. You confirm the removal in real time.

For your reference, the manual removal path is:

1. Sign in to https://admin.microsoft.com as Global Administrator
2. Navigate to **Settings > Partner relationships**
3. Locate the Simplicity IT relationship
4. Click **Remove roles** or **End relationship**
5. Confirm. The deletion completes immediately.

The relationship also auto-expires at the 14-day mark, so even if
the explicit teardown is skipped, no standing access persists.

## Questions

Contact your engagement lead at sales@simplicityitinc.com or via
the engagement shared Teams channel.
