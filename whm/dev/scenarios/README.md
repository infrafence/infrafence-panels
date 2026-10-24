Test-only variants of the replies in `../fixtures/` (which are copies of the agent's own outputs).
Same field names and shapes; only the values change. A file missing here falls back to `../fixtures/`.

- `empty/`: nothing banned, allowed, found or reported; no other security tools; no sites.
- `monitor/`: monitor mode on (detections reported, nothing banned).
- `restricted/`: a site whose document root does not belong to its account (`scannable: false`), a site
  without account or document root, and scheduled scans turned off.
- `hostile/`: markup, quotes and `javascript:` links in every text field, and invalid country codes, counts,
  score items and dates in `map` and `score`, for the escaping and validation tests.
