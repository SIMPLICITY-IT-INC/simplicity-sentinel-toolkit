# Simplicity IT Sentinel to Defender XDR Migration Toolkit

Open-source PowerShell toolkit for assessing a Microsoft Sentinel
environment's readiness to migrate to the unified Microsoft Defender XDR
portal. Produces a structured CSV plus an interactive HTML dashboard of
findings, classified OK / WARNING / INFORMATIONAL, that maps to the
seven days of Simplicity IT Inc.'s fixed-fee Sentinel to Defender XDR
1-Week Migration consulting engagement.

## Attribution

This toolkit is built on top of Mario Cuomo's
[Defender Adoption Helper](https://github.com/mariocuomo/Azure-Sentinel/tree/master/Tools/Sentinel-Defender-Helper-Script/New%20Version),
licensed under MIT (copyright Microsoft Corporation). Mario authored
the original three assessment modules (data retention, analytics
rules, automation rules) and the HTML dashboard renderer. Simplicity
IT Inc. retains his copyright headers on those files, preserves the
upstream MIT license, and adds five net-new modules covering
workbooks, Logic Apps playbooks, hunting queries, watchlists, and
data-connector equivalence mapping, plus an orchestrator script that
runs all eight checks and merges output.

If you find the upstream modules useful in isolation, use Mario's
repo directly. This fork exists so a Simplicity IT delivery team can
run one command and get a baseline assessment that mirrors the full
seven-day migration methodology, not just the three days the upstream
tool covers.

## Methodology mapping

| Toolkit module | Day in the 1-Week Migration methodology |
|----------------|------------------------------------------|
| Data retention check (upstream) | Day 1 (workspace audit) |
| Analytics rules check (upstream) | Day 3 (rule porting baseline) |
| Automation rules check (upstream) | Day 5 (automation rebuild baseline) |
| Workbooks inventory (new) | Day 4 (workbook + dashboard migration) |
| Playbooks deep-dive (new) | Day 5 (playbook + automation rebuild) |
| Hunting queries inventory (new) | Day 1 to Day 3 (KQL compatibility) |
| Watchlists inventory (new) | Day 2 (data-source mapping) |
| Connector equivalence map (new) | Day 2 (connector inventory) |

## Prerequisites

- PowerShell 5.1 or later, or PowerShell 7+ (cross-platform).
- A user account or service principal with **Microsoft Sentinel
  Reader** role on every target workspace. Read-only; the toolkit
  does not write to the customer tenant.
- Network access to `management.azure.com` and Microsoft Graph.
- Az PowerShell module installed (`Install-Module Az`).

## Quick start

```powershell
# 1. Configure target workspaces
notepad config\sentinelEnvironments.json

# 2. Run the orchestrator (runs all 8 modules, interactive auth)
.\src\Run-FullAssessment.ps1 -EnvironmentsFile .\config\sentinelEnvironments.json -AuthMode User

# 3. Open the dashboard
start .\output\dashboard.html

# 4. Optional: feed the CSV into SimpleChannel's Sentinel readiness
#    augmenter at https://channel.simpleintelligence.io/app/admin/sentinel-readiness
#    to produce four customer-facing deliverables in one click.
```

For service-principal authentication (recommended for repeatable
automation):

```powershell
.\src\Run-FullAssessment.ps1 -EnvironmentsFile .\config\sentinelEnvironments.json `
    -AuthMode App `
    -ClientId   "<app reg client id>" `
    -ClientSecret (ConvertTo-SecureString "<secret>" -AsPlainText -Force) `
    -TenantId   "<entra tenant id>"
```

## Output

After a run:

- `output/results.csv` -- one row per check, columns: workspace,
  category, checkName, itemName, status (OK / WARNING /
  INFORMATIONAL), details, recommendation.
- `output/dashboard.html` -- interactive single-page dashboard with
  per-workspace breakdown, filters, and PDF export.

The CSV is the canonical interchange format; the dashboard is for
operator review and customer screen-share moments.

## Modules

Each module is a standalone PowerShell function that queries the
Sentinel REST API and writes results to the shared CSV. The orchestrator
script invokes them in order.

| File | Purpose | Status |
|------|---------|--------|
| `src/DefenderAdoptionHelper.ps1` | Mario's original 3-in-1 module: retention, analytics rules, automation rules | upstream, MIT |
| `src/SimplicityWorkbooksInventory.ps1` | Enumerate workbooks; classify portability; flag broken queries | planned |
| `src/SimplicityPlaybookInventory.ps1` | Enumerate Logic Apps playbooks; walk action trees; surface external connectors needing reauth | planned |
| `src/SimplicityHuntingQueryInventory.ps1` | Enumerate saved hunting queries; syntactic compatibility check against unified Defender XDR query language | planned |
| `src/SimplicityWatchlistInventory.ps1` | Enumerate watchlists; classify post-migration validity | planned |
| `src/SimplicityConnectorMap.ps1` | Enumerate active connectors; map each to its Defender XDR equivalent or flag as Log-Analytics-only | planned |
| `src/Run-FullAssessment.ps1` | Orchestrator: runs all modules, merges CSV, opens dashboard | shipped |
| `src/Augment-Results.ps1` | Local AI augmenter: CSV + Anthropic API key, produces 4 customer deliverables (executive summary, Day 1 baseline, rule porting checklist, gap register) + a self-contained HTML brief. Offline / air-gapped alternative to SimpleChannel's web UI. | shipped |

Planned modules ship in subsequent releases. The upstream Mario module
works standalone today.

## Two ways to run the AI augmenter

After the orchestrator writes `output/results.csv`, you have two
options for producing customer-facing deliverables:

**Option A: SimpleChannel web UI** (recommended for delivery teams):

1. Sign in at `https://channel.simpleintelligence.io/`.
2. Navigate to **Admin > Sentinel Readiness Augmenter**.
3. Paste the CSV. Add optional customer-context note. Click run.
4. Download the self-contained HTML brief.

Audit trail (`McpAudit`), quota gates, multi-user access, no per-engineer
API key distribution.

**Option B: local CLI** (recommended for air-gapped / scripted use):

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."
.\src\Augment-Results.ps1 -CsvFile .\output\results.csv -CustomerHint "Acme Health"
```

Writes all four deliverables next to the CSV, plus
`sentinel-readiness-brief.html`. No web app, no auth, runs offline if
the Anthropic API endpoint is reachable.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Issues and pull requests
welcome.

## License

MIT. Copyright Microsoft Corporation (for upstream files) and
Simplicity IT Inc. (for net-new modules). See [LICENSE](./LICENSE)
and [NOTICE](./NOTICE).

## About Simplicity IT

[Simplicity IT Inc.](https://simplicityitinc.com/) is a Microsoft
Solutions Partner with active Security designation work. The 1-Week
Sentinel to Defender XDR Migration consulting offer is available on
the [Microsoft commercial marketplace](https://marketplace.microsoft.com/).
