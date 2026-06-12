<#
.SYNOPSIS
    Renders the AI-generated sentinel-readiness-brief.html to PDF
    using Microsoft Edge headless. No new dependencies; Edge ships
    on every Windows delivery laptop.

.DESCRIPTION
    Step between "augmenter produced the brief" and "hand the
    customer a PDF". Replaces the manual open-in-browser print-to-PDF
    step so the whole Day 1 deliverable chain can run unattended:

        Run-FullAssessment.ps1  ->  Augment-Results.ps1  ->  Export-BriefPdf.ps1

.PARAMETER HtmlFile
    Path to the brief HTML. Default: ..\output\sentinel-readiness-brief.html

.PARAMETER OutFile
    Output PDF path. Default: same folder, same name, .pdf extension.

.EXAMPLE
    .\Export-BriefPdf.ps1
    .\Export-BriefPdf.ps1 -HtmlFile ..\output\sentinel-readiness-brief.html -OutFile ..\output\Day1-Baseline.pdf

.NOTES
    Copyright Simplicity IT Inc., 2026. Licensed MIT.
#>

#Requires -Version 7

[CmdletBinding()]
param(
    [string]$HtmlFile = (Join-Path (Split-Path -Parent $PSScriptRoot) "output\sentinel-readiness-brief.html"),
    [string]$OutFile
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $HtmlFile)) {
    throw "Brief HTML not found: $HtmlFile. Run Augment-Results.ps1 first."
}
if (-not $OutFile) {
    $OutFile = [System.IO.Path]::ChangeExtension((Resolve-Path $HtmlFile).Path, ".pdf")
}

$edgePaths = @(
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
)
$edge = $edgePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) {
    throw "Microsoft Edge not found. Open the HTML in a browser and print to PDF manually."
}

$htmlUri = ([System.Uri](Resolve-Path $HtmlFile).Path).AbsoluteUri

Write-Host "Rendering $HtmlFile -> $OutFile" -ForegroundColor Cyan
& $edge --headless --disable-gpu --no-pdf-header-footer `
    --print-to-pdf="$OutFile" $htmlUri 2>$null | Out-Null

# Edge headless returns asynchronously on some builds; poll briefly.
$deadline = (Get-Date).AddSeconds(30)
while (-not (Test-Path $OutFile) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
}

if (-not (Test-Path $OutFile)) {
    throw "PDF was not produced within 30 seconds. Run Edge without --headless to inspect, or print manually."
}
$size = (Get-Item $OutFile).Length
Write-Host "PDF written: $OutFile ($([math]::Round($size/1kb)) KB)" -ForegroundColor Green
