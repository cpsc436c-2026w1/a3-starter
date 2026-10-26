# A3: a branch lake beside the company lakehouse

The assignment is [`a3.qmd`](a3.qmd), and its commands are in the collapsed 📋 Commands boxes inside it, placed where
each task first needs them. Read the task first, then open its box, then use these files. Run the shell scripts in CloudShell
(Region ca-central-1) after cloning this repository with the line in the assignment's "Before you start".

| File | What it is | Where you use it |
|---|---|---|
| `check_a3.sh` | checks your account for the earlier setups and A3's Setup steps 0 to 3, changes nothing, and says what to run for anything missing | Setup, and whenever a step fails |
| `setup_a3.sh` | copies the branch's raw files into your raw zone, creates the database `branch`, the table `branch.raw_households` and the Glue job `branch-receipts` | Setup, once |
| `branch_receipts.py` | the ready Glue job: till export (CSV) into `branch.receipts` | tasks 2 and 3 |
| `subscribe.sh` | subscribes your email to head office's replies | Setup |
| `report_task1.sql` | task 1's report, two parts blank | task 1.2 |
| `task1_variants.md` | three versions of the report and three measured figures to match | task 1.3 |
| `merge_members.sql` | the `MERGE` for the members' changes, two clauses blank | task 3.2 |
| `results.csv` | one row for each listed prediction and measurement. Predictions that have no row (2.2's lines to change, 3.2's changed rows and snapshot count, 3.3's snapshot list, 3.4, 3.5, and 4.2's query and noted files) go in the PDF | every task |

The raw files themselves come from `s3://436c-2026w1-public/a3/raw/`; `setup_a3.sh` copies them.

## Check your delivered report yourself (optional)

`features/task1_report.feature` holds head office's checks as scenarios (Gherkin, L9). Run them on the files your
`UNLOAD` wrote, either copied to CloudShell as below or named directly with
`REPORT=s3://436c-hq-inbox-940482406111/inbox/<your account id>/task1-<name>/`:

```bash
pip install --user behave
mkdir -p myreport && aws s3 cp s3://436c-hq-inbox-940482406111/inbox/<your account id>/task1-<name>/ myreport/ --recursive
REPORT=myreport python3 -m behave --tags=-headoffice features
```

Every scenario should pass. The one tagged `@headoffice` compares each share with head office's own figure, which
only head office can read: its reply tells you that result.
