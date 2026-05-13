# Changelog

## Unreleased

### Added

- Repository scaffold.
- Upstream `DefenderAdoptionHelper.ps1`, `sentinelEnvironments.json`,
  `dashboard.html` copied verbatim from Mario Cuomo's Defender
  Adoption Helper (MIT, Microsoft Corporation).
- `Run-FullAssessment.ps1` orchestrator (runs upstream module today,
  routes to extension modules as they ship).
- `Augment-Results.ps1` local AI augmenter: PowerShell script that
  calls the Anthropic API directly with the same prompt as the
  SimpleChannel-hosted augmenter, writes four deliverables and a
  self-contained HTML brief next to the input CSV. Offline /
  air-gapped alternative to the web UI.
- `SimplicityConnectorMap.ps1` (stub): connector-to-Defender-XDR
  equivalence inventory. CSV row schema is stable; integration test
  against a live tenant pending.
- `config/defenderXdrEquivalenceMap.json` (14 connector-kind entries):
  initial mapping table for the connector-map module.
- `NOTICE` file with full attribution to Mario Cuomo + Microsoft
  Corporation.
- `CONTRIBUTING.md` with maintenance commitments.
- `README.md` with methodology mapping table and quick-start.

### Planned (next releases)

- `SimplicityWorkbooksInventory.ps1`: workbook portability classifier.
- `SimplicityPlaybookInventory.ps1`: Logic Apps action-tree walker.
- `SimplicityHuntingQueryInventory.ps1`: KQL compatibility check.
- `SimplicityWatchlistInventory.ps1`: watchlist post-migration validity.
- Integration test pass against a real Sentinel workspace.
