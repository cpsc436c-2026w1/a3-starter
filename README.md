# A3: Building and querying data lakehouse

The assignment: <https://cpsc436c-2026w1.github.io/a3-starter/>

This repository holds the files the assignment uses. The assignment page is built from [`a3.qmd`](a3.qmd). On the
page, each task's commands are in a collapsed 📋 Commands box, under the step that first uses them.

To use the files:

1. Open CloudShell in the AWS console, in Region Canada (Central), ca-central-1.
2. Copy the files into CloudShell with the `git clone` line in the assignment's "Before you start".
3. For each task, read the task on the page, open its 📋 box, and run its commands in the `a3-starter` folder.

| File | What it is | Where you use it |
|---|---|---|
| `check_a3.sh` | reads your account and prints ✔ or ✗ for the earlier setups and for Setup steps 0 to 3. Each ✗ says what to run. It changes nothing | Setup, and whenever a step fails |
| `setup_a3.sh` | copies the branch's raw files into your raw zone, and creates the database `branch`, the table `branch.raw_households` and the Glue job `branch-receipts` | Setup step 3, once |
| `branch_receipts.py` | the script of the Glue job `branch-receipts`. It loads the till export (CSV) into `branch.receipts` | tasks 2.1, 2.2 and 3.3 |
| `subscribe.sh` | subscribes your email to head office's replies | Setup step 4 |
| `report_task1.sql` | task 1's report query, with two parts for you to write: the condition for Nutri-Score A and B, and the `GROUP BY` | task 1.2 |
| `task1_variants.md` | three versions of the report and three measured figures to match | task 1.3 |
| `merge_members.sql` | the `MERGE` statement for the members' changes, with its two clauses for you to write | task 3.2 |
| `results.csv` | 16 rows, one for each quantity you predict or measure, with a predicted and a measured value | every task |

A prediction or result that has no row in `results.csv` goes in your PDF under its task number: 2.2's lines to
change, 3.2's changed rows and snapshot count, 3.3's snapshot list, 3.4, 3.5, and 4.2's query and noted files.

You hand in your PDF, `results.csv` and Screenshots 1 and 2 on Canvas. The assignment's "Then submit to Canvas" lists
everything.

The other folders: `features/` holds head office's checks (below), `extensions/` holds the optional tasks, and `docs/`
and `diagrams/` build the assignment page. The raw files come from `s3://436c-2026w1-public/a3/raw/`, and
`setup_a3.sh` copies them.

## Check your delivered report yourself (optional)

`features/task1_report.feature` holds head office's checks as scenarios. A scenario is a short Given/When/Then test
written in plain text (Gherkin, L9).

In CloudShell, in the `a3-starter` folder, run the checks on the files your `UNLOAD` wrote. Copy the files into
CloudShell as below, or set `REPORT=s3://436c-hq-inbox-940482406111/inbox/<your account id>/task1-<any name>/`
instead of `REPORT=myreport`:

```bash
pip install --user behave
mkdir -p myreport && aws s3 cp s3://436c-hq-inbox-940482406111/inbox/<your account id>/task1-<any name>/ myreport/ --recursive
REPORT=myreport python3 -m behave --tags=-headoffice features
```

Every scenario that runs should pass. The scenario tagged `@headoffice` compares each share with head office's own
figure, which only head office can read, so `--tags=-headoffice` skips it here. Head office's reply gives you its
result by email, and as the file `s3://436c-hq-inbox-940482406111/inbox/<your account id>/replies/task1-<any name>.json`.
You can read `features/steps/report_steps.py` to see how each check works.
