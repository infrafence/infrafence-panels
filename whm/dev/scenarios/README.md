Test-only variants of the replies in `../fixtures/` (which are copies of the agent's own outputs).
Same field names and shapes; only the values change. A file missing here falls back to `../fixtures/`.

- `empty/`: nothing banned, allowed, found or reported; no other security tools; no sites.
- `monitor/`: monitor mode on (detections reported, nothing banned).
- `restricted/`: a site whose document root does not belong to its account (`scannable: false`), a site
  without account or document root, and scheduled scans turned off.
- `resolved/`: events and findings as agent 1.0.34 and later send them, with `subject`, `state`, `resolved_at`
  and `resolved_how` (the agent's own reference outputs, plus one more resolved event): a `db_exposed` resolved
  by a port closed, malware quarantined, files marked as expected or resolved in the dashboard. The default
  fixtures are from an older agent, without `state`: every event counts as open.
- `hostile/`: markup, quotes and `javascript:` links in every text field (`status` says `entitlement: "ok"` so
  the plan, itself hostile, does not hide the pages), and invalid country codes, counts,
  score items and dates in `map` and `score`, for the escaping and validation tests.
