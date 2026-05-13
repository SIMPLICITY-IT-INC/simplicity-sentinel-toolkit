# LinkedIn outreach to Mario Cuomo (draft, not sent)

**To:** Mario Cuomo, Microsoft Security
**From:** Ameer Abdur-Razzaaq, Principal, Simplicity IT Inc.
**Status:** draft for founder review and send

---

Subject: Defender Adoption Helper, attribution and a fork

Hi Mario,

I came across your Defender Adoption Helper script in the Azure-Sentinel
repo and want to share what we just published, partly so you have full
visibility and partly because I'd love your read on it.

Simplicity IT is a Microsoft Solutions Partner running a fixed-fee
Sentinel to Defender XDR 1-Week Migration consulting offer in the
commercial marketplace. Your tool covered three of the assessment
dimensions we need on Day 1 of every engagement, and rather than
rebuild what you've already built well, we forked your work into a
public toolkit, preserved your copyright header and the MIT license,
and named you in the README plus a separate NOTICE file.

Repo: https://github.com/SIMPLICITY-IT-INC/simplicity-sentinel-toolkit

Net-new in our fork (planned for the next two to three weeks):

- Workbook inventory + portability classifier
- Logic Apps playbook action-tree walker (external connectors that
  need reauth post-migration)
- Hunting query KQL compatibility check
- Watchlist post-migration validity
- Data-connector equivalence map (Sentinel kind -> Defender XDR
  equivalent, with notes on what stays in Log Analytics)

A couple of questions if you have time:

1. Would you want any of these contributed back upstream as PRs to
   your repo? I'd rather your repo be the home if it makes sense to
   you. Happy to follow your contribution preferences.
2. Are you tracking bugs / feature requests for the upstream module
   anywhere I should subscribe to?

We have a feature in our internal tooling (SimpleChannel) that takes
your CSV output and runs Claude over it to generate four customer-
facing deliverables (executive summary, Day 1 baseline, rule porting
checklist, classified gap register). The output of your script feeds
directly into a real customer engagement workflow. It is genuinely
useful.

Thank you for shipping it.

Ameer Abdur-Razzaaq
Principal, Simplicity IT Inc.
https://simplicityitinc.com/

---

## Send checklist

- [ ] Read Mario's recent LinkedIn posts; check tone matches.
- [ ] Confirm repo is public and renders correctly.
- [ ] Confirm NOTICE file is at repo root and easy to find.
- [ ] Send via LinkedIn direct message; do not cc anyone.
- [ ] Note any reply in `docs/upstream-correspondence.md` for the
      maintenance record.
