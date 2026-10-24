# Quality gate: your scenarios run on every commit

After every commit to a branch table (a Glue job's write, `MERGE`, `DELETE`, `OPTIMIZE`, a property change), a Lambda
function runs your Gherkin scenarios against that table and writes the result to
`s3://436c-glue-<account>/branch/checks/results/<table>/`.

**Why the trigger is a metadata file.** An Iceberg write lands its data files first, then one new
`metadata/*.metadata.json`: the commit. A trigger on that file fires once per commit, after the data is complete. A
trigger on the data files would fire once per file, before the commit, while readers still see the old snapshot.
The results go outside `branch/tables/`, so writing them never triggers the gate again.

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
bash setup_gate.sh features             # after each change to features/ (no redeploy)
```

Commit something, for example `ALTER TABLE branch.members SET TBLPROPERTIES ('vacuum_min_snapshots_to_keep' = '1')`
(the default value: it changes nothing but is still a commit), wait a minute, then:

```bash
aws s3 ls s3://436c-glue-<account>/branch/checks/results/ --recursive
```

Try a scenario on your own machine first, without the Lambda:

```bash
pip install --user behave
python3 -m behave features -D TABLE=branch.receipts --tags @receipts,@all
```

## Steps you can use

```gherkin
Given the table that was just committed
Then no row has <SQL condition>                    # e.g. is_lyon = false, quantity <= 0
Then the query "<SQL with {table}>" returns <n>    # any count query
Then the table has at most <n> snapshots
Then the table has at most <n> data files
Then no data file is smaller than <n> MB
Then no data file has more than <n> row groups     # skipped when no file records its row groups
Then the data files do not overlap on <column>
```

Tag each scenario with the tables it applies to: `@members`, `@receipts`, `@price_events`, or `@all`.

Remove it when you are done: `bash teardown_gate.sh`.
