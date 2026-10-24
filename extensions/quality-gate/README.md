# Quality gate: your scenarios run on every commit

After every commit to a branch table (a Glue job's write, `MERGE`, `DELETE`, `OPTIMIZE`, a property change), a Lambda
function runs your Gherkin scenarios against that table and writes the result to
`s3://436c-glue-<account>/branch/checks/results/<table>/`.

**Why the trigger is a metadata file.** An Iceberg commit writes its data files first, then a new
`metadata/*.metadata.json`, then points the Glue catalog at that file. A trigger on the metadata file fires after the
data files are written. The function then waits until the catalog points at the new file, so the scenarios read the
new snapshot. A trigger on the data files would fire once per file, before the commit, while readers still see the
old snapshot. The results go outside `branch/tables/`, so writing them never triggers the gate again.

## Files

| File | What it is |
|---|---|
| `features/branch_lake.feature` | two example scenarios; write yours below them |
| `features/steps/branch_steps.py` | the steps your scenarios can use (each runs a small Athena query) |
| `handler.py` | the Lambda function: downloads `features/` from your bucket, runs behave for the committed table |
| `setup_gate.sh` | copies `features/` to your bucket, creates the role, the function and the trigger |
| `teardown_gate.sh` | removes the trigger, the function and the role |

## Run it

```bash
cd extensions/quality-gate
bash setup_gate.sh                      # once
bash setup_gate.sh features             # after each change to features/, scenarios or steps (no redeploy)
```

Commit something in Athena, for example `ALTER TABLE branch.members SET TBLPROPERTIES ('vacuum_min_snapshots_to_keep' =
'2')`. The next time, set it back to `'1'`, the default. Each new value is a commit; setting the value the table
already has is not, and writes no metadata file. Wait a minute, then:

```bash
aws s3 ls s3://436c-glue-<account>/branch/checks/results/ --recursive
aws s3 cp s3://436c-glue-<account>/branch/checks/results/members/<file>.json -    # one result
```

Each result names the scenarios, their status and, for a failed or skipped one, the reason. No result after two
minutes: `aws logs tail /aws/lambda/436c-quality-gate --since 10m` shows what the function printed.

Try your scenarios in CloudShell first, without the Lambda:

```bash
pip install --user behave==1.3.3
python3 -m behave features -D TABLE=branch.receipts --tags @receipts,@all
```

## Steps you can use

```gherkin
Given the table that was just committed
Then no row has <SQL condition>                    # e.g. quantity <= 0, is_lyon IS DISTINCT FROM true
Then the query "<SQL with {table}>" returns <n>    # any count query
Then the table has at most <n> snapshots
Then the table has at most <n> data files
Then no data file is smaller than <n> MB
Then no data file has more than <n> row groups     # skipped when no file records its row groups (after OPTIMIZE)
Then the data files do not overlap on <column>     # skipped when every partition has one file
```

Tag each scenario with the tables it applies to: `@members`, `@receipts`, `@price_events`, or `@all`.

Remove it when you are done: `bash teardown_gate.sh`. It removes the trigger, the function, its role and its logs.
