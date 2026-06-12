# Delivery Runbook: Sentinel to Defender XDR Pre-Migration Assessment

Step-by-step instructions for Simplicity IT delivery engineers running
the toolkit against a customer's Sentinel environment. This is the
Day 1 activity of the 1-Week Sentinel to Defender XDR Migration
engagement. Total hands-on time is roughly 30 to 45 minutes per
customer, most of it waiting on API calls.

**What you get at the end:** `output/results.csv` (raw findings),
`output/dashboard.html` (interactive review), and four AI-generated
customer deliverables (executive summary, Day 1 baseline, rule-porting
checklist, gap register).

**What the toolkit checks today:** the three upstream assessment
modules (Defender XDR data retention, analytics rules, automation
rules). The five Simplicity extension modules (workbooks, playbooks,
hunting queries, watchlists, connector map) are in development; the
orchestrator prints a "not yet shipped; skipping" notice for each.
That is expected, not an error.

---

## Part 1: One-time workstation setup

Do these once per laptop, not per customer.

**Step 1. Install PowerShell 7 or later.**

```powershell
winget install Microsoft.PowerShell
```

Why: the scripts use PowerShell 7 syntax. Windows PowerShell 5.1
(the built-in one) will fail with parser errors. Check what you have
with `$PSVersionTable.PSVersion`; you want 7.x.

**Step 2. Install the Az.Accounts module.**

```powershell
Install-Module Az.Accounts -Scope CurrentUser -Repository PSGallery
```

Why: the toolkit calls the Azure management REST API with a bearer
token it obtains through `Connect-AzAccount`. No other Az modules are
needed; the scripts talk to the API directly.

**Step 3. Clone the toolkit.**

```powershell
git clone https://github.com/SIMPLICITY-IT-INC/simplicity-sentinel-toolkit.git
cd simplicity-sentinel-toolkit
```

Why: always run from a fresh clone or a `git pull`ed copy so you get
the current module set. Do not copy loose scripts between customer
folders; the orchestrator resolves its module paths relative to the
repo layout.

---

## Part 2: Per-customer setup

**Step 4. Confirm your access in the customer tenant.**

You need the **Microsoft Sentinel Reader** role (or higher) on every
Log Analytics workspace you will assess. Reader on the subscription
also works. Ask the customer to grant your account, or use the App
mode service principal described in Step 6.

Why: every check is read-only. The toolkit never writes to the
customer environment, so never accept more than Reader; it protects
both sides.

**Step 5. Fill in the environments file.**

Open `config\sentinelEnvironments.json` and replace the placeholders.
One JSON object per workspace; assess multiple workspaces in one run
by adding more objects to the array:

```json
[
  {
    "subscriptionId": "00000000-0000-0000-0000-000000000000",
    "resourceGroupName": "rg-security-prod",
    "workspaceName": "law-sentinel-prod"
  }
]
```

Where to find these values: in the Azure portal, open Microsoft
Sentinel, select the workspace, and read subscription ID, resource
group, and workspace name from the Overview blade.

Tip: save the filled file as `config\<customer>-environments.json`
instead of editing the template in place. The config folder is
gitignored for `*-environments.json` patterns; never commit a real
customer file.

**Step 6. Choose your authentication mode.**

- **User mode (default, use this unless told otherwise).** The script
  opens a browser window; sign in with your account that has Sentinel
  Reader in the customer tenant. Nothing to pre-configure.
- **App mode (for repeat or scripted runs).** Requires the customer
  to create an App Registration with the Sentinel Reader role on the
  workspace, and to hand you the client ID, tenant ID, and a client
  secret. Use this when the engagement includes scheduled
  re-assessment or when interactive login is blocked by the
  customer's conditional access.

---

## Part 3: Run the assessment

**Step 7. Run the orchestrator.**

User mode:

```powershell
cd src
.\Run-FullAssessment.ps1 -EnvironmentsFile ..\config\contoso-environments.json -AuthMode User
```

App mode:

```powershell
cd src
$secret = Read-Host -AsSecureString -Prompt "Client secret"
.\Run-FullAssessment.ps1 -EnvironmentsFile ..\config\contoso-environments.json `
  -AuthMode App -ClientId "<app-client-id>" -TenantId "<customer-tenant-id>" -ClientSecret $secret
```

What it does: authenticates, runs the upstream Defender Adoption
Helper checks against every workspace in your config, writes the
combined findings to `output\results.csv`, and opens
`output\dashboard.html` in your browser when finished. Expect the
skip notices for modules 2 through 6 described at the top of this
runbook. Add `-SkipDashboard` if you are running unattended.

**Step 8. Review the dashboard before generating anything
customer-facing.**

The dashboard loads `results.csv` and classifies each finding as OK,
WARNING, or INFORMATIONAL. Sanity-check three things:

1. Row count is plausible (a workspace with 80 analytics rules should
   not produce 6 rows; if it does, your account is missing read
   permission on part of the workspace).
2. Every workspace from your config file appears.
3. WARNING items make sense against what you saw in the kickoff call.

Why: the AI augmenter in the next step writes the executive summary
from this CSV. Garbage in, confident-sounding garbage out. The
engineer's review here is the quality gate.

---

## Part 4: Generate the customer deliverables

Two paths produce identical deliverables. Use the web path by
default; use the local path when you cannot reach the web app or you
are scripting.

**Step 9 (web path, preferred). Use the SimpleChannel augmenter.**

1. Open `https://channel.simpleintelligence.io/app/admin/sentinel-readiness`
   and sign in with your Simplicity IT account.
2. Upload `output\results.csv`.
3. In the customer-context box, give one line of context:
   customer name, rough endpoint count, regulated or not. Example:
   "Contoso Health, 1,200 endpoints, HIPAA-regulated."
4. Generate. Download the four deliverables it produces.

**Step 9 (local path, alternative). Run the local augmenter.**

```powershell
$env:ANTHROPIC_API_KEY = "<key from the team password manager>"
.\Augment-Results.ps1 -CsvFile ..\output\results.csv `
  -CustomerHint "Contoso Health, 1200 endpoints, HIPAA-regulated"
```

What it does: one Claude API call that writes five files to
`output\`: `executive-summary.md`, `day1-baseline.md`,
`rule-porting-checklist.md`, `gap-register.csv`, and
`sentinel-readiness-brief.html` (self-contained; open in a browser
and print to PDF for the customer copy).

Key handling: get the API key from the team password manager each
time. Never put it in a file inside this repo, never commit it, and
clear it from your session afterward with
`Remove-Item Env:\ANTHROPIC_API_KEY`.

**Step 10. Review and edit the AI output.**

Read all four deliverables before they leave your laptop. You are
checking that: the executive summary matches the dashboard's actual
risk picture, every rule in the porting checklist exists in the
customer's workspace, and the gap register's must_fix items are
genuinely blocking. Fix anything that is wrong; the AI drafts, the
engineer owns.

**Step 11. Package the Day 1 deliverables.**

Per the engagement methodology, the customer receives:

- `Day1-Baseline.pdf` (print `sentinel-readiness-brief.html` to PDF,
  or render `day1-baseline.md`)
- `Day1-RawData\` folder containing `results.csv`

Deliver through the engagement's shared folder, not email
attachments.

---

## Part 5: Cleanup

**Step 12. Clear customer data off your laptop at engagement end.**

```powershell
Remove-Item ..\output\* -Exclude dashboard.html -Force
Remove-Item ..\config\contoso-environments.json -Force
```

Why: `results.csv` contains the customer's rule names, workspace
layout, and security posture. It has no business persisting on a
consultant laptop after the engagement closes. `dashboard.html` is
toolkit code, not customer data; it stays.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Connect-AzAccount` browser window never appears | Conditional access blocks device-code or browser flow | Switch to App mode (Step 6) |
| 403 errors per workspace | Missing Sentinel Reader on that workspace | Re-check role assignment; subscription Reader also needs the SecurityInsights read scope |
| `results.csv` has far fewer rows than expected | Partial permissions, or one workspace in the config is wrong | Compare dashboard workspaces against config entries |
| Parser errors on script start | Running Windows PowerShell 5.1 | Run under `pwsh` (PowerShell 7) |
| Augmenter throws "API key not set" | Env var not present in this session | Set `$env:ANTHROPIC_API_KEY` in the same window you run the script |
| CSV over 500 KB warning | Very large estate | Expected; the augmenter truncates its model input. Deliverables still generate; review extra carefully |

## Scope and attribution

The three live assessment modules are Mario Cuomo's Defender Adoption
Helper (MIT, copyright Microsoft Corporation), run unmodified. The
orchestrator, augmenter, and extension-module roadmap are Simplicity
IT additions (MIT). Keep both copyright headers intact if you copy
files out of this repo.
