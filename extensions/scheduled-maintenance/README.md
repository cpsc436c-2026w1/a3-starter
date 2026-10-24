# Scheduled maintenance: task 4's plan, running every night

EventBridge Scheduler (L11) calls Athena's `StartQueryExecution` directly, with no Lambda in between: `OPTIMIZE` at
02:00 and `VACUUM` at 02:30, Vancouver time, on `branch.members`, `branch.receipts` and `branch.price_events`. Each
statement is its own schedule, because Athena runs one statement per call. The role `436c-maintenance` lets the
scheduler run them on your tables.

## Run it

```bash
cd extensions/scheduled-maintenance
bash setup_schedule.sh --now     # test: each OPTIMIZE 3 minutes from now, each VACUUM 5 minutes from now
bash setup_schedule.sh           # nightly, for 30 days
```

Check a run in the Athena console's **Recent queries**, or in CloudShell:

```bash
aws athena list-query-executions --work-group primary --max-items 6
```

The one-time schedules are named `now-…` and delete themselves after they run, so a test never replaces the nightly
schedules. The nightly ones stop after 30 days; remove them earlier with `bash teardown_schedule.sh`.

Two things to know:

- `VACUUM` removes the files `OPTIMIZE` replaced only when their snapshot is older than the table's
  `vacuum_max_snapshot_age_seconds`. With task 4.2's 60 seconds, the test's `VACUUM` two minutes later removes them;
  with a longer age it removes nothing yet.
- With a 60-second age, `VACUUM` also deletes files a running Glue job has written but not yet committed, which
  breaks that job's commit. Do not run a Glue job on a branch table between 02:00 and 02:45, or during a test.

## Files

| File | What it is |
|---|---|
| `setup_schedule.sh` | creates the role, the schedule group `436c-maintenance` and one schedule per statement |
| `teardown_schedule.sh` | removes every schedule in the group, the group and the role |

Set `TABLES="members receipts"` before the command to schedule fewer tables.
