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

That command prints bare IDs. To see each run's statement, state and Data scanned, run:

```bash
aws athena batch-get-query-execution \
  --query-execution-ids $(aws athena list-query-executions --work-group primary --max-items 6 --query 'QueryExecutionIds[]' --output text) \
  --query 'QueryExecutions[].[Query,Status.State,Statistics.DataScannedInBytes]' --output table
```

If nothing ran, look at the schedule itself. A one-time `now-…` schedule that is still there after its time has not
run, because it deletes itself once it has:

```bash
aws scheduler list-schedules --group-name 436c-maintenance --query 'Schedules[].Name'
aws scheduler get-schedule --group-name 436c-maintenance --name <a name from the list, such as now-optimize-members>
```

In the CloudWatch console, **Metrics**, open the namespace `AWS/Scheduler`. `TargetErrorCount` counts calls Athena
refused, and `InvocationDroppedCount` counts calls the scheduler gave up on after its retries. Both stay at 0 when
the schedules work.

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
| [`setup_schedule.sh`](setup_schedule.sh) | creates the role, the schedule group `436c-maintenance` and one schedule per statement |
| [`teardown_schedule.sh`](teardown_schedule.sh) | removes every schedule in the group, the group and the role |

Set `TABLES="members receipts"` before the command to schedule fewer tables.
