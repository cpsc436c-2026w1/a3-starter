# A3: a branch lake beside the company lakehouse

The assignment is [`a3.qmd`](a3.qmd) and the commands are in [`job-aid.md`](job-aid.md). Read the assignment first, then
the job aid, then use these files. Run the shell scripts in CloudShell
(Region ca-central-1) after downloading them with the line in the assignment's Setup.

| File | What it is | Where you use it |
|---|---|---|
| `setup_a3.sh` | copies the branch's raw files into your raw zone, creates the database `branch`, the table `branch.raw_households` and the Glue job `branch-receipts` | Setup, once |
| `branch_receipts.py` | the ready Glue job: till export (CSV) into `branch.receipts` | tasks 2 and 3 |
| `subscribe.sh` | subscribes your email to head office's replies | Setup |
| `report_task1.sql` | task 1's report, two parts blank | task 1.2 |
| `task1_variants.md` | three versions of the report and three measured figures to match | task 1.3 |
| `merge_members.sql` | the `MERGE` for the members' changes, two clauses blank | task 3.2 |
| `results.csv` | one row per prediction and measurement; add rows as you go | every task |

The raw files themselves come from `s3://436c-2026w1-public/a3/raw/`; `setup_a3.sh` copies them.
