<#
.SYNOPSIS
    Local / offline AI augmenter. Takes the results.csv produced by
    Run-FullAssessment.ps1 and produces four customer deliverables
    using the Anthropic Claude API directly.

.DESCRIPTION
    Same prompt, same output shape as the SimpleChannel-hosted
    Sentinel readiness augmenter at
    https://channel.simpleintelligence.io/app/admin/sentinel-readiness
    but runs entirely on the delivery engineer's laptop. Useful for:

      - Air-gapped customer environments where the engineer can't
        reach the SimpleChannel web app.
      - Repeatable scripted use (CI, scheduled re-augmentation).
      - Operators who prefer terminal over browser.

    Writes four files to the output folder:
      output/executive-summary.md
      output/day1-baseline.md
      output/rule-porting-checklist.md
      output/gap-register.csv
      output/sentinel-readiness-brief.html  (self-contained, print to PDF)

.PARAMETER CsvFile
    Path to results.csv produced by the orchestrator.

.PARAMETER CustomerHint
    Optional free-text hint Claude uses to tailor the executive summary
    (customer name, industry, rough endpoint count, regulated status).

.PARAMETER ApiKey
    Anthropic API key. Defaults to $env:ANTHROPIC_API_KEY.

.PARAMETER BaseUrl
    Anthropic API endpoint. Defaults to $env:ANTHROPIC_BASE_URL or
    "https://api.anthropic.com". Use a SIG-routed Azure AI Foundry
    endpoint if you have one configured.

.PARAMETER Model
    Anthropic model ID. Defaults to "claude-sonnet-4-6".

.EXAMPLE
    .\Augment-Results.ps1 -CsvFile ..\output\results.csv -CustomerHint "Acme Health, 1200 endpoints, HIPAA-regulated"

.NOTES
    Copyright Simplicity IT Inc., 2026. Licensed MIT.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CsvFile,
    [string]$CustomerHint,
    [string]$ApiKey = $env:ANTHROPIC_API_KEY,
    [string]$BaseUrl,
    [string]$Model = "claude-sonnet-4-6"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $CsvFile)) {
    throw "CSV file not found: $CsvFile"
}
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "Anthropic API key not set. Pass -ApiKey or set `$env:ANTHROPIC_API_KEY."
}
if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl = if ($env:ANTHROPIC_BASE_URL) { $env:ANTHROPIC_BASE_URL } else { "https://api.anthropic.com" }
}

$csvText = Get-Content $CsvFile -Raw
if ($csvText.Length -gt 500000) {
    Write-Warning "CSV is over 500 KB; truncating to first 500 KB for the model call."
    $csvText = $csvText.Substring(0, 500000)
}

$customerLine = if ($CustomerHint) { "Customer context: $CustomerHint." } else { "Customer context: not provided." }

$systemPrompt = @"
You are a senior Microsoft Sentinel to Defender XDR migration architect at Simplicity IT, a Microsoft Solutions Partner. You receive raw CSV output from an open-source pre-migration assessment tool and produce five customer-ready deliverables, including a per-finding enrichment that is structured for downstream LLM-driven remediation.

The CSV uses the v2 per-finding schema (locked 2026-06-12): every WARNING row carries a stable FindingId column plus CurrentValue, ExpectedValue, SeverityRationale, and RemediationActionId columns. You must echo these back verbatim in enrichedFindings so the downstream remediation pipeline can bind to them.

DELIVERABLES, in priority order:

1. executiveSummary: 3 to 4 paragraphs aimed at the customer's CISO. Plain English, no jargon. Cover: current state, headline risks, what Simplicity IT will fix during the 7-day migration, post-migration posture. State the March 31, 2027 unified-portal cutover deadline once, plainly, with no scaremongering.

2. day1Baseline: engineer-facing baseline. Markdown headings: Workspace inventory, Analytics rules summary, Automation rules summary, Retention posture, Identified blockers, Recommended pre-migration cleanup.

3. rulePortingChecklist: Day 3 runbook. Numbered list of analytics rules flagged WARNING or INFORMATIONAL, each with: rule name, current state, action required, estimated minutes.

4. gapRegister: array of structured gaps. Each entry classifies as must_fix (blocks cutover), nice_to_have (post-cutover hardening), or informational (no action).

5. enrichedFindings: per-finding remediation context structured for downstream LLM execution. ONE ENTRY PER WARNING ROW IN THE CSV. Each entry must:
   - echo findingId, remediationActionId, currentValue, expectedValue, severityRationale verbatim from the matching CSV row
   - add humanContext (1 to 2 sentences explaining the finding to a SOC engineer who hasn't seen this customer before)
   - add riskIfIgnored (1 sentence on the operational impact if this is left unremediated through cutover)
   - add recommendedAction (1 to 3 sentences on the concrete next step, referencing the remediationActionId when one of the documented action tokens is present)
   - add automatable (boolean: true if remediationActionId is one of automation.trigger.title-rewrite, automation.condition.provider-remove, analytics.incident-reopening.disable; false otherwise)

OUTPUT FORMAT: JSON only, no prose preamble. Schema:
{
  "executiveSummary": "string (markdown allowed)",
  "day1Baseline": "string (markdown with ## headings)",
  "rulePortingChecklist": "string (markdown numbered list)",
  "gapRegister": [{"item": "string", "category": "must_fix"|"nice_to_have"|"informational", "rationale": "string", "estimatedMinutes": number}],
  "enrichedFindings": [{"findingId": "string", "ruleOrSubject": "string", "section": "string", "remediationActionId": "string", "currentValue": "string", "expectedValue": "string", "severityRationale": "string", "humanContext": "string", "riskIfIgnored": "string", "recommendedAction": "string", "automatable": boolean}],
  "rawSummaryStats": {"totalFindings": number, "okCount": number, "warningCount": number, "informationalCount": number}
}

CONSTRAINTS:
- Never use em-dashes (one of these: U+2014) or en-dashes (U+2013). Use colons, commas, periods, parentheses.
- Be specific. Reference actual rule names, table names, check categories from the CSV.
- Echo findingId and remediationActionId VERBATIM from the CSV. Do not invent new tokens. Do not modify a findingId; the downstream remediation tool keys on it.
- Match Simplicity IT brand voice: trusted advisor, consultative, regulated-industry-aware, no marketing fluff.
"@

$userMessage = @"
$customerLine

Here is the raw CSV output from the pre-migration assessment tool. Produce the four deliverables per the system prompt.

``````csv
$csvText
``````
"@

$body = @{
    model       = $Model
    max_tokens  = 8000
    system      = $systemPrompt
    messages    = @(
        @{ role = "user"; content = $userMessage }
    )
} | ConvertTo-Json -Depth 8 -Compress

$headers = @{
    "x-api-key"          = $ApiKey
    "anthropic-version"  = "2023-06-01"
    "content-type"       = "application/json"
}

Write-Host "Calling Anthropic ($Model)..." -ForegroundColor Cyan
$startTime = Get-Date
try {
    $response = Invoke-RestMethod -Uri "$BaseUrl/v1/messages" -Method Post -Headers $headers -Body $body -TimeoutSec 120
} catch {
    throw "Anthropic call failed: $($_.Exception.Message)"
}
$duration = (Get-Date) - $startTime
Write-Host "  Returned in $([int]$duration.TotalSeconds) seconds." -ForegroundColor Green

# Concatenate any text-content blocks.
$rawText = ($response.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join ""

# Strip ```json fences if present.
$rawText = $rawText -replace '^\s*```(?:json)?\s*', '' -replace '\s*```\s*$', ''
$parsed = $rawText | ConvertFrom-Json

# Output folder = sibling of the input CSV.
$outputDir = Split-Path -Parent $CsvFile
if (-not $outputDir) { $outputDir = "." }

$execPath = Join-Path $outputDir "executive-summary.md"
$baselinePath = Join-Path $outputDir "day1-baseline.md"
$checklistPath = Join-Path $outputDir "rule-porting-checklist.md"
$gapsPath = Join-Path $outputDir "gap-register.csv"
$briefPath = Join-Path $outputDir "sentinel-readiness-brief.html"
$enrichedJsonPath = Join-Path $outputDir "enriched-findings.json"
$enrichedCsvPath = Join-Path $outputDir "enriched-findings.csv"

Set-Content -Path $execPath -Value $parsed.executiveSummary -Encoding UTF8
Set-Content -Path $baselinePath -Value $parsed.day1Baseline -Encoding UTF8
Set-Content -Path $checklistPath -Value $parsed.rulePortingChecklist -Encoding UTF8

# Gap register as CSV.
$parsed.gapRegister | Select-Object item, category, rationale, estimatedMinutes |
    Export-Csv -Path $gapsPath -NoTypeInformation -Encoding UTF8

# Per-finding enrichment artifacts (v2). JSON is what the LLM remediation
# pipeline consumes; CSV is the human-reviewable form.
if ($parsed.enrichedFindings) {
    $parsed.enrichedFindings | ConvertTo-Json -Depth 8 |
        Set-Content -Path $enrichedJsonPath -Encoding UTF8
    $parsed.enrichedFindings |
        Select-Object findingId, ruleOrSubject, section, remediationActionId,
                      currentValue, expectedValue, severityRationale,
                      humanContext, riskIfIgnored, recommendedAction, automatable |
        Export-Csv -Path $enrichedCsvPath -NoTypeInformation -Encoding UTF8
}

# Build the self-contained HTML brief, same shape as the SimpleChannel
# web version.
$stats = $parsed.rawSummaryStats
$mustFix = $parsed.gapRegister | Where-Object { $_.category -eq "must_fix" }
$niceToHave = $parsed.gapRegister | Where-Object { $_.category -eq "nice_to_have" }
$informational = $parsed.gapRegister | Where-Object { $_.category -eq "informational" }
$totalGapMinutes = ($parsed.gapRegister | Measure-Object -Property estimatedMinutes -Sum).Sum
$totalGapHours = [math]::Round($totalGapMinutes / 60.0, 1)
$generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm") + " local"

function ConvertTo-HtmlEscaped($s) {
    if (-not $s) { return "" }
    return ($s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&#39;')
}
function ConvertTo-HtmlFromMarkdown($s) {
    if (-not $s) { return "" }
    $lines = ($s -replace "`r`n", "`n").Split("`n")
    $sb = New-Object System.Text.StringBuilder
    $inUl = $false; $inOl = $false; $para = @()
    foreach ($raw in $lines) {
        $line = $raw.TrimEnd()
        if (-not $line) {
            if ($para.Count -gt 0) { [void]$sb.Append("<p>$(ConvertTo-HtmlEscaped($para -join ' '))</p>"); $para = @() }
            if ($inUl) { [void]$sb.Append("</ul>"); $inUl = $false }
            if ($inOl) { [void]$sb.Append("</ol>"); $inOl = $false }
            continue
        }
        if ($line -match '^##\s+(.+)$') {
            if ($para.Count -gt 0) { [void]$sb.Append("<p>$(ConvertTo-HtmlEscaped($para -join ' '))</p>"); $para = @() }
            if ($inUl) { [void]$sb.Append("</ul>"); $inUl = $false }
            if ($inOl) { [void]$sb.Append("</ol>"); $inOl = $false }
            [void]$sb.Append("<h3>$(ConvertTo-HtmlEscaped($Matches[1]))</h3>")
        } elseif ($line -match '^###\s+(.+)$') {
            if ($para.Count -gt 0) { [void]$sb.Append("<p>$(ConvertTo-HtmlEscaped($para -join ' '))</p>"); $para = @() }
            [void]$sb.Append("<h4>$(ConvertTo-HtmlEscaped($Matches[1]))</h4>")
        } elseif ($line -match '^[-*]\s+(.+)$') {
            if ($para.Count -gt 0) { [void]$sb.Append("<p>$(ConvertTo-HtmlEscaped($para -join ' '))</p>"); $para = @() }
            if ($inOl) { [void]$sb.Append("</ol>"); $inOl = $false }
            if (-not $inUl) { [void]$sb.Append("<ul>"); $inUl = $true }
            [void]$sb.Append("<li>$(ConvertTo-HtmlEscaped($Matches[1]))</li>")
        } elseif ($line -match '^\d+\.\s+(.+)$') {
            if ($para.Count -gt 0) { [void]$sb.Append("<p>$(ConvertTo-HtmlEscaped($para -join ' '))</p>"); $para = @() }
            if ($inUl) { [void]$sb.Append("</ul>"); $inUl = $false }
            if (-not $inOl) { [void]$sb.Append("<ol>"); $inOl = $true }
            [void]$sb.Append("<li>$(ConvertTo-HtmlEscaped($Matches[1]))</li>")
        } else {
            $para += $line
        }
    }
    if ($para.Count -gt 0) { [void]$sb.Append("<p>$(ConvertTo-HtmlEscaped($para -join ' '))</p>") }
    if ($inUl) { [void]$sb.Append("</ul>") }
    if ($inOl) { [void]$sb.Append("</ol>") }
    return $sb.ToString()
}

$gapRows = @()
foreach ($g in $mustFix) {
    $gapRows += "<tr><td><strong>$(ConvertTo-HtmlEscaped($g.item))</strong></td><td>$(ConvertTo-HtmlEscaped($g.rationale))</td><td style='text-align:right' class='dim'>$($g.estimatedMinutes) min</td></tr>"
}
$niceRows = @()
foreach ($g in $niceToHave) {
    $niceRows += "<tr><td><strong>$(ConvertTo-HtmlEscaped($g.item))</strong></td><td>$(ConvertTo-HtmlEscaped($g.rationale))</td><td style='text-align:right' class='dim'>$($g.estimatedMinutes) min</td></tr>"
}
$infoRows = @()
foreach ($g in $informational) {
    $infoRows += "<tr><td><strong>$(ConvertTo-HtmlEscaped($g.item))</strong></td><td>$(ConvertTo-HtmlEscaped($g.rationale))</td><td style='text-align:right' class='dim'>$($g.estimatedMinutes) min</td></tr>"
}

$customerHintLine = if ($CustomerHint) { "Customer context: $(ConvertTo-HtmlEscaped($CustomerHint)) &middot; Generated $generatedAt" } else { "Generated $generatedAt" }

# Per-finding enrichment rows (v2). Rendered as expandable sections in the
# brief; the same data also lands in enriched-findings.json for the LLM
# remediation pipeline.
$findingsRows = @()
if ($parsed.enrichedFindings) {
    foreach ($f in $parsed.enrichedFindings) {
        $autoBadge = if ($f.automatable) { "<span style='background:#46B491;color:#fff;padding:1pt 6pt;font-size:8pt;border-radius:2pt;'>auto</span>" } else { "<span style='background:#666;color:#fff;padding:1pt 6pt;font-size:8pt;border-radius:2pt;'>manual</span>" }
        $findingsRows += @"
<div class='finding'>
  <div class='finding-head'>
    <div><strong>$(ConvertTo-HtmlEscaped($f.ruleOrSubject))</strong> <span class='dim'>&middot; $(ConvertTo-HtmlEscaped($f.section))</span></div>
    <div>$autoBadge <span class='action-id'>$(ConvertTo-HtmlEscaped($f.remediationActionId))</span></div>
  </div>
  <div class='finding-grid'>
    <div class='cell'><div class='cell-label'>Current</div><div>$(ConvertTo-HtmlEscaped($f.currentValue))</div></div>
    <div class='cell'><div class='cell-label'>Expected</div><div>$(ConvertTo-HtmlEscaped($f.expectedValue))</div></div>
  </div>
  <div class='cell'><div class='cell-label'>Why this matters</div><div>$(ConvertTo-HtmlEscaped($f.severityRationale)) $(ConvertTo-HtmlEscaped($f.humanContext))</div></div>
  <div class='cell'><div class='cell-label'>Risk if ignored</div><div>$(ConvertTo-HtmlEscaped($f.riskIfIgnored))</div></div>
  <div class='cell'><div class='cell-label'>Recommended action</div><div>$(ConvertTo-HtmlEscaped($f.recommendedAction))</div></div>
  <div class='finding-id'>findingId: <code>$(ConvertTo-HtmlEscaped($f.findingId))</code></div>
</div>
"@
    }
}

$html = @"
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Sentinel readiness brief</title>
<style>
  @page { size: Letter; margin: 0.55in 0.65in; }
  * { box-sizing: border-box; }
  body { font-family: "Segoe UI", -apple-system, system-ui, sans-serif; color: #182C43; margin: 0; font-size: 10.5pt; line-height: 1.45; }
  .brand-bar { background: #182C43; color: #fff; padding: 16pt 22pt; margin: -0.55in -0.65in 18pt -0.65in; display: flex; align-items: center; justify-content: space-between; }
  .brand-bar .wordmark { font-size: 17pt; font-weight: 700; letter-spacing: 0.5pt; }
  .brand-bar .wordmark .green { color: #46B491; }
  .brand-bar .tagline { font-size: 8.5pt; color: #46B491; letter-spacing: 1.5pt; }
  .doc-type { background: #46B491; color: #fff; padding: 3pt 10pt; font-size: 8.5pt; font-weight: 600; letter-spacing: 1pt; border-radius: 3pt; }
  h1 { font-size: 22pt; margin: 0 0 4pt 0; }
  h1 .accent { color: #46B491; }
  .subtitle { font-size: 11pt; color: #46B491; font-weight: 600; }
  .url-line { font-size: 9pt; color: #666; margin-bottom: 16pt; }
  h2 { font-size: 12pt; margin: 18pt 0 8pt 0; color: #46B491; border-bottom: 1.5pt solid #46B491; padding-bottom: 3pt; text-transform: uppercase; letter-spacing: 0.5pt; }
  h3 { font-size: 11pt; margin: 10pt 0 4pt 0; color: #182C43; }
  h4 { font-size: 10pt; margin: 8pt 0 4pt 0; color: #46B491; }
  table { width: 100%; border-collapse: collapse; margin: 6pt 0; font-size: 9.5pt; }
  th { background: #182C43; color: #fff; text-align: left; padding: 5pt 8pt; }
  td { padding: 5pt 8pt; border-bottom: 0.5pt solid #ddd; vertical-align: top; }
  .dim { color: #666; }
  .stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10pt; }
  .stat { border: 1pt solid #ddd; border-left: 4pt solid #46B491; padding: 10pt 14pt; }
  .stat.ok { border-left-color: #46B491; }
  .stat.warning { border-left-color: #DC740E; }
  .stat.info { border-left-color: #0078D4; }
  .stat .label { font-size: 8.5pt; color: #666; text-transform: uppercase; letter-spacing: 1pt; }
  .stat .num { font-size: 24pt; font-weight: 700; line-height: 1; }
  .footer { margin-top: 20pt; padding-top: 10pt; border-top: 0.5pt solid #ddd; font-size: 8pt; color: #666; display: flex; justify-content: space-between; }
  .finding { border: 0.5pt solid #ddd; border-left: 3pt solid #DC740E; padding: 10pt 12pt; margin: 8pt 0; page-break-inside: avoid; }
  .finding-head { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8pt; font-size: 10pt; }
  .finding-head .action-id { font-family: "Consolas", monospace; font-size: 8.5pt; background: #f4f6f9; padding: 1pt 6pt; border-radius: 2pt; color: #182C43; }
  .finding-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8pt; margin-bottom: 6pt; }
  .cell { margin-bottom: 6pt; }
  .cell-label { font-size: 7.5pt; color: #46B491; text-transform: uppercase; letter-spacing: 0.5pt; margin-bottom: 2pt; }
  .finding-id { font-size: 7.5pt; color: #666; margin-top: 6pt; padding-top: 4pt; border-top: 0.5pt dotted #ddd; }
  .finding-id code { font-family: "Consolas", monospace; }
</style></head>
<body>
<div class="brand-bar">
  <div><div class="wordmark">Simplicity<span class="green">IT</span></div><div class="tagline">IT MADE SIMPLE</div></div>
  <div class="doc-type">SENTINEL READINESS BRIEF</div>
</div>

<h1>Pre-Migration <span class="accent">Readiness</span> Report</h1>
<p class="subtitle">Sentinel to Defender XDR: per-finding context for the 7-day migration.</p>
<p class="url-line">$customerHintLine</p>

<h2>Assessment summary</h2>
<div class="stats">
  <div class="stat"><div class="label">Total findings</div><div class="num">$($stats.totalFindings)</div></div>
  <div class="stat ok"><div class="label">OK</div><div class="num">$($stats.okCount)</div></div>
  <div class="stat warning"><div class="label">Warnings</div><div class="num">$($stats.warningCount)</div></div>
  <div class="stat info"><div class="label">Informational</div><div class="num">$($stats.informationalCount)</div></div>
</div>
<p class="dim">Estimated effort to close all gaps: $totalGapHours hours ($totalGapMinutes minutes across $($parsed.gapRegister.Count) items).</p>

<h2>Executive summary</h2>
$(ConvertTo-HtmlFromMarkdown($parsed.executiveSummary))

<h2>Day 1 baseline</h2>
$(ConvertTo-HtmlFromMarkdown($parsed.day1Baseline))

<h2>Rule porting checklist (Day 3)</h2>
$(ConvertTo-HtmlFromMarkdown($parsed.rulePortingChecklist))

<h2>Gap register</h2>

<h3>Must fix before cutover ($($mustFix.Count))</h3>
$(if ($mustFix.Count -gt 0) { "<table><thead><tr><th style='width:30%'>Item</th><th>Why it blocks cutover</th><th style='width:12%;text-align:right'>Effort</th></tr></thead><tbody>$($gapRows -join '')</tbody></table>" } else { "<p>No cutover blockers identified.</p>" })

$(if ($niceToHave.Count -gt 0) { "<h3>Nice to have, post-cutover ($($niceToHave.Count))</h3><table><thead><tr><th style='width:30%'>Item</th><th>Rationale</th><th style='width:12%;text-align:right'>Effort</th></tr></thead><tbody>$($niceRows -join '')</tbody></table>" } else { "" })

$(if ($informational.Count -gt 0) { "<h3>Informational ($($informational.Count))</h3><table><thead><tr><th style='width:30%'>Item</th><th>Note</th><th style='width:12%;text-align:right'>Effort</th></tr></thead><tbody>$($infoRows -join '')</tbody></table>" } else { "" })

$(if ($findingsRows.Count -gt 0) { "<h2>Per-finding remediation context</h2><p class='dim'>One entry per WARNING from the assessment. Each entry pairs the observed state with the Defender requirement, a plain-English risk note, and the recommended remediation action. The <strong>auto</strong> badge indicates the fix is mechanical and can be executed by the AI-driven remediation pipeline under the binding safety contract. <strong>manual</strong> findings require customer SOC review.</p>$($findingsRows -join '')" } else { "" })

<div class="footer"><span>Simplicity IT Inc. &middot; Pre-Migration Readiness Report</span><span>simplicityitinc.com</span></div>
</body></html>
"@

Set-Content -Path $briefPath -Value $html -Encoding UTF8

Write-Host ""
Write-Host "Wrote:" -ForegroundColor Green
Write-Host "  $execPath"
Write-Host "  $baselinePath"
Write-Host "  $checklistPath"
Write-Host "  $gapsPath"
if ($parsed.enrichedFindings) {
    Write-Host "  $enrichedJsonPath  (input for the LLM remediation pipeline)"
    Write-Host "  $enrichedCsvPath"
}
Write-Host "  $briefPath"
Write-Host ""
Write-Host "Next: render the brief to Pre-Migration-Readiness-Report.pdf via Export-BriefPdf.ps1, OR open $briefPath in a browser and print to PDF." -ForegroundColor Cyan
