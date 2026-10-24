# Scheduled maintenance: task 4's plan, running every night

EventBridge Scheduler (L11) calls Athena's `StartQueryExecution` directly, with no Lambda in between: `OPTIMIZE` at
02:00 and `VACUUM` at 02:30, Vancouver time, on `branch.members`, `branch.receipts` and `branch.price_events`. Each
statement is its own schedule, because Athena runs one statement per call. The role `436c-maintenance` lets the
scheduler run them on your tables.

## Run it

```bash
cd extensions/scheduled-maintenance
bash setup_schedule.sh --now     # test: every statement once, starting in about 3 minutes
bash setup_schedule.sh           # nightly
```

Check a run in the Athena console's **Recent queries**, or in CloudShell:

```bash
aws athena list-query-executions --work-group primary --max-items 6
```

The one-time schedules delete themselves after they run. Remove the nightly ones when you are done:
`bash teardown_schedule.sh`.

## Files

| File | What it is |
|---|---|
| `setup_schedule.sh` | creates the role, the schedule group `436c-maintenance` and one schedule per statement |
| `teardown_schedule.sh` | removes every schedule in the group, the group and the role |

Set `TABLES="members receipts"` before the command to schedule fewer tables.
