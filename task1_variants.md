# Task 1.3: three versions of the report, three measured figures

We ran three versions of the report on the company lakehouse (2026-10-24, Athena engine version 3). Match each
version to its Data scanned, and say why it reads what it reads.

| Version | What changed against the report |
|---|---|
| V1 | one more column of `consumption` in the result: `sum(c.quantity) AS units` |
| V2 | one month only: `WHERE c.event_ts >= TIMESTAMP '2025-12-01 00:00:00' AND c.event_ts < TIMESTAMP '2026-01-01 00:00:00'` |
| V3 | the join without the catalogue: total spend per month and segment, no Nutri-Score, no `LEFT JOIN` to `catalogue` |

| Measured | Data scanned |
|---|---|
| A | 5,462.3 MB |
| B | 211.2 MB |
| C | 7,844.3 MB |
