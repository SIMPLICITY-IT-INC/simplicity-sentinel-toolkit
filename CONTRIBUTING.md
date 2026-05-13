# Contributing

Thanks for considering a contribution to the Simplicity IT Sentinel
Migration Toolkit.

## Maintenance commitment

Simplicity IT Inc. operates this repository under the following
service levels:

- **Critical-bug response:** within 5 business days of report
  through a GitHub issue.
- **Monthly review:** issues + PRs reviewed at least once per
  calendar month.
- **Breaking changes:** announced at least 30 days ahead via repo
  release notes.

No SLA is offered for community pull requests; we review when
time allows.

## Reporting issues

File an issue with:

- Toolkit version (the git commit you cloned).
- PowerShell version output: `$PSVersionTable`.
- The minimum command that reproduces the problem.
- The CSV row or dashboard panel that surfaced the unexpected
  behaviour.

Please do not include real customer tenant IDs, workspace IDs, or
rule names. Use anonymized substitutes.

## Pull requests

1. Fork.
2. Create a feature branch.
3. Write or update tests where applicable (PowerShell Pester for
   logic; we will introduce an integration test harness in a
   future release).
4. Update the README + CHANGELOG if your change is user-visible.
5. Ensure every new file carries a copyright header.
6. Open a PR; we review monthly at minimum.

## Upstream contribution

The upstream tool we extend is Mario Cuomo's Defender Adoption
Helper. When we fix bugs in his three original modules
(`src/DefenderAdoptionHelper.ps1`), we file the same fix upstream.
Contributors who fix bugs in those files are encouraged to do the
same; tag your PR `upstream-candidate` to flag this.

Net-new modules (the `Simplicity*.ps1` files) do not have an upstream
counterpart yet, so they stay here.

## License of contributions

By submitting a PR you agree your contribution is licensed under
the MIT License documented in `LICENSE`.
