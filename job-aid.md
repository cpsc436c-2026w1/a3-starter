# A3 job aid

The assignment says what to do and why. The job aid says how, in the order you need it. Region `ca-central-1`
throughout. Replace `<account>` with your 12-digit account number, which CloudShell prints with:

```bash
aws sts get-caller-identity --query Account --output text
```

Each step names its place: **CloudShell** (the `>_` icon in the console's top bar), the **Athena query editor**, or
the **Glue console**.

## Data scanned limit, once per account

Tutorial 1 set a Data scanned limit of 2 GB on the workgroup `primary`. Task 1's report reads more, so raise the
limit to 10 GB.

**In the console:**

1. Athena → **Workgroups** → `primary` → **Execution controls** tab → **Edit controls**.
2. Set **Data scanned limit** to 10 GB → **Save**.

**Or in CloudShell:**

```bash
aws athena update-work-group --work-group primary \
  --configuration-updates BytesScannedCutoffPerQuery=10000000000
```

The command changes only the limit. The result location from tutorial 1 stays.

**Check it** in CloudShell. You should see `10000000000`:

```bash
aws athena get-work-group --work-group primary \
  --query WorkGroup.Configuration.BytesScannedCutoffPerQuery
```

<!--src: https://docs.aws.amazon.com/athena/latest/ug/workgroups-setting-control-limits-cloudwatch.html (console path, cancel, billing) | https://docs.aws.amazon.com/cli/latest/reference/athena/update-work-group.html | b3-t1-athena-rides/setup_athena.sh:40-41 (same flag, 2 GB as 2000000000) -->

## Company lakehouse, `branch` database and `shelf` data source

**Data source**, on the left of the query editor, sets the catalog for table names you do not write in full.

| Data source | What it holds | Name in full |
|---|---|---|
| `course` | the company lakehouse, read-only | `course.course_lake.<table>` |
| `AwsDataCatalog` | your own catalog: the `branch` database | `awsdatacatalog.branch.<table>` (`branch.<table>` under this Data source) |
| `shelf` | the shelf-price app's DynamoDB table, through a Lambda connector | `shelf.default.course_shelf_prices` |

1. **Athena query editor**, Data source `course`: run `SHOW TABLES IN course_lake`. You should see the company
   tables, `consumption` among them.
2. **CloudShell**: register the connector once, as Setup step 2 says:

   ```bash
   aws athena create-data-catalog --name shelf --type LAMBDA \
     --parameters function=arn:aws:lambda:ca-central-1:940482406111:function:436c-ddb-connector
   ```

3. **Athena query editor**: reload the Data source list. You should see `shelf`. Run:

   ```sql
   SHOW TABLES IN shelf.default;
   ```

   You should see `course_shelf_prices`, and other tables of the course account that you cannot read. A query on
   `course_shelf_prices` is a federated query, through the connector.
4. Data source `AwsDataCatalog`: run `SHOW TABLES IN branch`. After setup you should see `raw_households`.

A statement that names every table in full runs under any Data source. Numbers from `shelf` arrive as `decimal(38,9)`: cast a key with `CAST(store_id AS bigint)`
before you join on it.

<!--src: https://docs.aws.amazon.com/cli/latest/reference/athena/create-data-catalog.html (LAMBDA type, function=<arn>) | demos/a3-hq/README.md (connector, decimal(38,9) note; cross-account invoke grant LtHubOrgInvoke) | b3-t1-athena-rides/README.md §2 (Data source list, names in full) -->

Checked from a student sandbox account on 2026-10-24: `SHOW TABLES IN shelf.default` lists `course_shelf_prices`.

## Reading what a query and a Glue run cost

**Athena query.** After a query ends, the editor shows **Run time** and **Data scanned** under the results, and
the **Query stats** tab shows the same. Athena bills $5.50 per TB of Data scanned in `ca-central-1`, with a 10 MB
minimum per query.

**Glue run.** In CloudShell, after the run ends:

```bash
aws glue get-job-runs --job-name rides-month --max-items 1 \
  --query 'JobRuns[0].[ExecutionTime,DPUSeconds]'
```

The first number is the run time in seconds, the second the DPU-seconds. If the second is `null`, multiply the
seconds by the job's DPUs: two G.1X workers are 2 DPUs. Glue 5.0 bills $0.44 per DPU-hour, per second, with a
1-minute minimum.

**Worked example: tutorial 2's rides.**

| Item | Measured | Arithmetic | Cost |
|---|---|---|---|
| Glue run, `rides-month` | `[189, 379.0]` | 379 / 3,600 × $0.44 | $0.046 a run |
| Same run, every night for a year | | $0.046 × 365 | about $17 |
| Week report in Athena | 13.1 MB | 13.1 MB / 1,000,000 MB per TB × $5.50 | $0.00007 |
| `MERGE` on the zones | under 1 KB | billed as 10 MB: 10 / 1,000,000 × $5.50 | $0.000055 |

A run shorter than a minute is billed as a minute: a 40-second run on 2 DPUs costs 2 × 60 DPU-seconds.

<!--src: aws-pricing get_pricing AmazonAthena ca-central-1, CAN1-DataScannedInTB, 5.50 USD/TB, "minimum 10MB for each successful or cancelled queries" (read 2026-10-23) | syllabus-preview/facts.yml l7.glue.dpu_hr_51 0.44 (below Glue 6.0) | https://docs.aws.amazon.com/whitepapers/latest/big-data-analytics-options/aws-glue.html (per second, 1-minute minimum) | https://docs.aws.amazon.com/glue/latest/webapi/API_JobRun.html (ExecutionTime, DPUSeconds may be unset) | b3-t2-glue-rides/README.md step 2, step 6 (13.1 MB; [189, 379.0]) | demos/l11check/runs/athena-statements-20261019-011459.jsonl (MERGE 951 bytes) -->

## UNLOAD to head office's inbox

`UNLOAD` runs a query and writes its result as files to an S3 folder. Head office reads every folder under
`s3://436c-hq-inbox-940482406111/inbox/<account>/`. Test the path with a toy report before task 1.

1. **Athena query editor**:

   ```sql
   UNLOAD (SELECT city, count(*) AS stores
           FROM course.course_lake.stores
           GROUP BY city)
   TO 's3://436c-hq-inbox-940482406111/inbox/<account>/toy-stores/'
   WITH (format = 'JSON', compression = 'NONE');
   ```

   `format = 'JSON'` writes JSON Lines: one JSON record per line. Set `compression = 'NONE'` to write plain-text JSON Lines.
   Without it, Athena uses the documented JSON default, gzip.
2. The folder must be empty. A second `UNLOAD` into the same folder fails with `HIVE_PATH_ALREADY_EXISTS`: use a
   new folder name each time.
3. **CloudShell**, within a minute, list the replies and print one:

   ```bash
   aws s3 ls s3://436c-hq-inbox-940482406111/inbox/<account>/replies/
   aws s3 cp s3://436c-hq-inbox-940482406111/inbox/<account>/replies/toy-stores.json -
   ```

   You should see `toy-stores.json`, saying head office does not know a report called `toy-stores`: the path
   works. Head office checks folders whose name starts with `task1-`.

**Replies by email.** In CloudShell, in the `a3-starter` folder:

```bash
bash subscribe.sh <your email>
```

Confirm the subscription in the email from AWS Notifications. Every reply then also arrives by email.

<!--src: https://docs.aws.amazon.com/athena/latest/ug/unload.html (syntax, empty TO location, gzip default for JSON) | demos/l11check/runs/athena-statements-20261019-011459.jsonl (compression = 'NONE' gives plain JSON Lines; second UNLOAD fails HIVE_PATH_ALREADY_EXISTS) | demos/a3-hq/checker/checker.py:102-113 (unknown report name reply, replies/<report>.json) | starter/subscribe.sh -->

The starter files, `subscribe.sh` among them, are in CloudShell after the Setup's `git clone` of `a3-starter`.

## MERGE

`MERGE` matches each incoming row to the table by a key. It updates the rows that match and inserts the rest.
Tutorial 2's extra exercise, run in the **Athena query editor**:

```sql
MERGE INTO tutorial.zones t
USING tutorial.zone_changes c
ON t.locationid = c.locationid
WHEN MATCHED THEN UPDATE SET borough = c.borough, zone = c.zone, service_zone = c.service_zone
WHEN NOT MATCHED THEN INSERT (locationid, borough, zone, service_zone)
  VALUES (c.locationid, c.borough, c.zone, c.service_zone);
```

| Clause | What it does |
|---|---|
| `MERGE INTO tutorial.zones t` | the target: an Iceberg table, here with the alias `t` |
| `USING tutorial.zone_changes c` | the incoming rows: a table or a query in brackets |
| `ON t.locationid = c.locationid` | the key that pairs an incoming row with a target row |
| `WHEN MATCHED THEN UPDATE SET …` | for a pair: set the target's columns from the incoming row |
| `WHEN NOT MATCHED THEN INSERT (…) VALUES (…)` | for an incoming row with no pair: add it. List the target's columns bare, and the values with the source alias |

`WHEN MATCHED THEN DELETE` removes the paired target row, and `AND <condition>` after `MATCHED` narrows a clause.
For each incoming row, only the first clause that applies runs.

What you should see: 265 zones before, 266 after (two updated, one inserted), and 266 after the same `MERGE` again.
Each `MERGE` adds one snapshot.

**Two incoming rows for one key.** If two incoming rows match the same target row, the `MERGE` fails and changes
nothing:

```
MERGE_TARGET_ROW_MULTIPLE_MATCHES: One MERGE target table row matched more than one source row
```

Keep one incoming row per key before the `MERGE`.

**Deleting the rows another table lists.** A `DELETE` can take its keys from a query:

```sql
DELETE FROM tutorial.zones
WHERE locationid IN (SELECT locationid FROM tutorial.zone_changes WHERE zone = 'New test zone');
```

<!--src: https://docs.aws.amazon.com/athena/latest/ug/merge-into-statement.html (synopsis, first WHEN clause wins, error on multiple matches, INSERT/VALUES prefixes) | b3-t2-glue-rides/sql/06_extra_merge.sql and README §4 (265 → 266 → 266) | demos/l11check/runs/athena-statements-20261019-011459.jsonl (error text, one snapshot per MERGE) -->

## Changing a Glue job from CSV to JSON Lines

Create the second job as a clone of the first. A clone keeps the job's Spark settings and parameters:
`--datalake-formats iceberg`, the `--conf` settings that define `glue_catalog`, `--BUCKET` and `--DAY`. A job created
from scratch lacks them and fails when it writes to `glue_catalog`.

1. **Glue console** → **ETL jobs** → select `branch-receipts` → **Actions** → **Clone job**.
2. Give the clone a new name.
3. **Job details** tab → **Advanced properties**: set the script filename to a new file in
   `s3://436c-glue-<account>/branch/jobs/`, so that saving the clone's script leaves `branch_receipts.py` as it is.
   Task 3.3 runs `branch-receipts` again.
4. **Script** tab: edit the script, then **Save**.
5. On the **Runs** tab, open the run. For a failed run, you see its **Error message**; select **Output logs** to open
   the full log.

Step 3 matters whichever path the clone starts with: a script file of its own is the only way an edit cannot reach
`branch_receipts.py`.

**Worked diff on another file.** A made-up chain's fridge sensors write one JSON Lines file an hour, with records
such as `{"sensor_id": "f-07", "store_id": 12, "read_at": "2026-10-16T23:00:05Z", "temp_c": 3.4}`. The diff turns
`branch_receipts.py` into a job that loads them into `demo.fridge_readings`. It is an example to read, not to run.

A job reads every file under the folder `RAW` names, subfolders included: a `RAW` that ends at `dt=<day>/` reads every
hour of that day.

```diff
-RAW = f"s3://{args['BUCKET']}/branch/raw/receipts/dt={args['DAY']}/"
-TABLE = "glue_catalog.branch.receipts"
+RAW = f"s3://{args['BUCKET']}/demo/raw/fridge_temps/dt={args['DAY']}/"
+TABLE = "glue_catalog.demo.fridge_readings"

-# 1. Read the day's till export: one CSV file with a header row
-raw = spark.read.option("header", "true").csv(RAW)
+# 1. Read the day's sensor files: JSON Lines, one record per line
+raw = spark.read.json(RAW)

-receipts = raw.select(
-    F.col("receipt_id"),
-    ...
-    F.col("payment_method"),
-)
+readings = raw.select(
+    F.col("sensor_id"),
+    F.col("store_id").cast("int"),
+    F.to_timestamp("read_at").alias("read_at"),
+    F.col("temp_c").cast("double"),
+)

-exists = spark.sql("SHOW TABLES IN glue_catalog.branch LIKE 'receipts'").count() > 0
+exists = spark.sql("SHOW TABLES IN glue_catalog.demo LIKE 'fridge_readings'").count() > 0

-        .partitionedBy(F.days("sold_at"))
+        .partitionedBy(F.days("read_at"))
```

Rename `receipts` to `readings` on the remaining lines. The lines that changed:

| Line | Why it changed |
|---|---|
| `RAW`, `TABLE` | the input folder and the target table |
| the reader | `spark.read.json` reads JSON Lines and takes the column names from the records |
| the `select` | the file's own fields; a time arrives as a string and needs `to_timestamp`, and the casts fix each type |
| `exists` | the check looks for the new table's name |
| `partitionedBy` | the new table's time column |

The table properties, `repartition` and `job.commit()` stay as they are.

<!--src: https://docs.aws.amazon.com/glue/latest/dg/managing-jobs-chapter.html (Actions → Clone job) | starter/setup_a3.sh:47-49 (--datalake-formats, --conf, --BUCKET, --DAY) | starter/branch_receipts.py | https://spark.apache.org/docs/latest/sql-data-sources-json.html (JSON Lines by default, schema inferred) -->

## One price in four places

The four statements for task 3.5, one per place. Each shows a price and the time it carries.

1. **The app's DynamoDB table**, Data source `shelf` (a federated query):
   ```sql
   SELECT price_eur, updated_at FROM shelf.default.course_shelf_prices
   WHERE store_id = 43 AND product_code = '3068320011707';
   ```
2. **The hourly export in your raw zone**, in CloudShell:
   ```bash
   aws s3 cp s3://436c-glue-<account>/branch/raw/price_events/dt=2026-10-16/hour=23/changes.jsonl - | grep '"store_id": 43, "product_code": "3068320011707"'
   ```
3. **Your branch table**, Data source `AwsDataCatalog`:
   ```sql
   SELECT price_eur, changed_at FROM branch.price_events
   WHERE store_id = 43 AND product_code = '3068320011707';
   ```
4. **The company table**, Data source `course`:
   ```sql
   SELECT current_unit_price_eur, observed_at FROM course.course_lake.current_prices
   WHERE store_id = 43 AND product_code = '3068320011707';
   ```

<!--src: statements 1, 3 and 4 ran in the sandbox, run log tools/e2e/run-20261023-24.md, 2026-10-23/24 | statement 2: the grep pattern matches one line of data/branch-raw/price_events/dt=2026-10-16/hour=23/changes.jsonl (format from demos/a3-hq/updater.py json.dumps), not run in CloudShell -->

## Table properties, OPTIMIZE and VACUUM

All in the **Athena query editor**, one statement at a time, for each of `branch.members`, `branch.receipts` and
`branch.price_events`. The statements below use `branch.<table>`.

1. Set how old a snapshot may get before `VACUUM` expires it, then check:

   ```sql
   ALTER TABLE branch.<table> SET TBLPROPERTIES ('vacuum_max_snapshot_age_seconds' = '60');
   SHOW TBLPROPERTIES branch.<table>;
   ```

   You should see `vacuum_max_snapshot_age_seconds` with `60`. The default is 432000 seconds (5 days). VACUUM
   always keeps at least one snapshot.
2. Compact:

   ```sql
   OPTIMIZE branch.<table> REWRITE DATA USING BIN_PACK;
   ```

   `OPTIMIZE` leaves a partition alone until it has at least 5 small files, or a data file has at least 2 delete
   files (Athena's defaults). It bills the data it reads.
3. Wait one minute after the table's last change, then expire old snapshots:

   ```sql
   VACUUM branch.<table>;
   ```

   `VACUUM` expires only snapshots older than 60 seconds. If old snapshots remain, wait a minute and run it again.
4. Look at the result:

   ```sql
   SELECT count(*) AS files, sum(record_count) AS rows FROM branch."<table>$files";
   SELECT snapshot_id, committed_at, operation, summary['added-delete-files'] AS delete_files,
          summary['total-delete-files'] AS all_delete_files
   FROM branch."<table>$snapshots" ORDER BY committed_at;
   ```

   To read the table as it was at one of those snapshots, paste its `snapshot_id` as a number:

   ```sql
   SELECT count(*) FROM branch.<table> FOR VERSION AS OF <snapshot_id> WHERE <condition>;
   ```

`$files` lists data files only. Delete files show in the `$snapshots` summaries, or in S3. To count every file
in S3, take the folder from any `file_path` in `$files` and list it in CloudShell:

```bash
aws s3 ls s3://436c-glue-<account>/<folder up to data/> --recursive | wc -l
```

In our run of A3 (2026-10-24), `OPTIMIZE` rewrote each branch table into one file: a day's 32 or 64 small files,
and a table whose first data file had two delete files, from the `MERGE` and from the `DELETE`.

Where the files are: a table a Glue job created is under `branch/tables/branch.db/<table>/`, and a table made with
`CREATE TABLE ... AS SELECT` is under the `location` you gave it.

<!--src: https://docs.aws.amazon.com/athena/latest/ug/vacuum-statement.html (default 432000 s, vacuum_min_snapshots_to_keep 1, time travel fails) | https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-creating-tables.html (optimize_rewrite_data_file_threshold 5, optimize_rewrite_delete_file_threshold 2) | https://docs.aws.amazon.com/athena/latest/ug/optimize-statement.html (syntax, billed by data scanned) | b3-t2-glue-rides/sql/03_compact.sql, 04_expire_old_snapshots.sql, README step 5 (one-minute wait) | BUILD-STATE.md "Already settled" ($files data only) -->

## S3 Lifecycle rule on the raw zone

A Lifecycle rule tells S3 to delete objects under a prefix once they reach an age.

1. **CloudShell**: check whether your bucket already has a configuration:

   ```bash
   aws s3api get-bucket-lifecycle-configuration --bucket 436c-glue-<account>
   ```

   `NoSuchLifecycleConfiguration` means none. If you see rules, copy them into the file in step 2:
   `put-bucket-lifecycle-configuration` replaces the bucket's whole configuration.
2. Write the rule to a file:

   ```bash
   cat > lifecycle.json <<'EOF'
   {"Rules": [{"ID": "raw-30-days", "Filter": {"Prefix": "branch/raw/"},
               "Status": "Enabled", "Expiration": {"Days": 30}}]}
   EOF
   ```

3. Apply it, then check:

   ```bash
   aws s3api put-bucket-lifecycle-configuration --bucket 436c-glue-<account> \
     --lifecycle-configuration file://lifecycle.json
   aws s3api get-bucket-lifecycle-configuration --bucket 436c-glue-<account>
   ```

   You should see the rule `raw-30-days` with `"Status": "Enabled"`.

The rule deletes a file by its age in S3, counted from when the file was written, and never on request: S3 removes
expired files in the background, some time after they reach 30 days.

<!--src: https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutBucketLifecycleConfiguration.html (replaces existing configuration) | https://docs.aws.amazon.com/cli/latest/reference/s3api/put-bucket-lifecycle-configuration.html (JSON shape) | https://docs.aws.amazon.com/AmazonS3/latest/userguide/troubleshoot-lifecycle.html (expiration is asynchronous) | l7-spark-glue/setup_glue.sh (sets no lifecycle rule) -->

## Shut down

1. **CloudShell**: delete both Glue jobs:

   ```bash
   aws glue delete-job --job-name branch-receipts
   aws glue delete-job --job-name <your price job>
   ```

   Then set the Data scanned limit back to tutorial 1's 2 GB:

   ```bash
   aws athena update-work-group --work-group primary \
     --configuration-updates BytesScannedCutoffPerQuery=2000000000
   ```

2. Optional, **Athena query editor**, once your numbers are in `results.csv`:

   ```sql
   DROP TABLE IF EXISTS branch.members;
   DROP TABLE IF EXISTS branch.receipts;
   DROP TABLE IF EXISTS branch.price_events;
   ```

   Dropping an Iceberg table also deletes its data files. `branch.raw_households` is not an Iceberg table: dropping
   it removes only the catalog entry, and the raw files stay in the raw zone.
3. Keep the query history. Athena keeps it for 45 days, and it is your evidence. Head office keeps your delivered
   reports.

<!--src: b3-t2-glue-rides/README.md §5 (delete-job) | https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg-drop-table.html (DROP deletes data) | https://docs.aws.amazon.com/athena/latest/ug/querying-keeping-query-history.html (45 days) | starter/setup_a3.sh:30-38 (raw_households is EXTERNAL_TABLE, JSON) -->
