#!/bin/bash
# A3 setup: run once in CloudShell (Region ca-central-1), after tutorial 1's setup_athena.sh and L7's setup_glue.sh.
#   bash setup_a3.sh
# 1. copies the branch's raw files into your raw zone, s3://436c-glue-<account>/branch/raw/
# 2. creates your Glue database branch and the table branch.raw_households over the members' change files
# 3. copies the job script to your bucket and creates the Glue job branch-receipts (Glue 5.0, 2 G.1X workers)
# Running it again is safe: files are copied again, the table and the job are updated.
set -euo pipefail
export AWS_DEFAULT_REGION=ca-central-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
ROLE=436c-glue-notebook
BUCKET=${BUCKET:-436c-glue-$ACCOUNT}
SRC=436c-2026w1-public/a3/raw
JOB=branch-receipts
DAY=2026-10-16
echo "account $ACCOUNT"

aws iam get-role --role-name "$ROLE" >/dev/null 2>&1 || { echo "STOP: role $ROLE not found. Run L7's setup first:"; \
  echo "  curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/l7-spark-glue/main/setup_glue.sh && bash setup_glue.sh"; exit 1; }
aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1 || { echo "STOP: bucket $BUCKET not found. Run L7's setup_glue.sh first"; exit 1; }

# 1. The raw files. The source lets anyone read a file by its name but not list the folder, so _files.json names them.
aws s3 cp "s3://$SRC/_files.json" "s3://$BUCKET/branch/raw/_files.json" --only-show-errors
for KEY in $(aws s3 cp "s3://$SRC/_files.json" - | python3 -c 'import json,sys; [print(f["key"]) for f in json.load(sys.stdin)["files"]]'); do
  aws s3 cp "s3://$SRC/$KEY" "s3://$BUCKET/branch/raw/$KEY" --only-show-errors
done
echo "raw     s3://$BUCKET/branch/raw/ ($(aws s3 ls "s3://$BUCKET/branch/raw/" --recursive | wc -l) files)"

# 2. The database and the members' change files as a table (JSON Lines, one record per line).
aws glue get-database --name branch >/dev/null 2>&1 || aws glue create-database --database-input Name=branch >/dev/null
TABLE=$(python3 - "$BUCKET" <<'PY'
import json, sys
cols = [("op", "string"), ("household_id", "bigint"), ("home_store_id", "int"), ("size", "int"), ("diet", "string"),
        ("loyalty_card", "boolean"), ("city", "string"), ("is_lyon", "boolean"), ("marketing_consent", "boolean")]
print(json.dumps({"Name": "raw_households", "TableType": "EXTERNAL_TABLE", "Parameters": {"classification": "json"},
  "StorageDescriptor": {"Columns": [{"Name": n, "Type": t} for n, t in cols],
    "Location": f"s3://{sys.argv[1]}/branch/raw/households/",
    "InputFormat": "org.apache.hadoop.mapred.TextInputFormat",
    "OutputFormat": "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
    "SerdeInfo": {"SerializationLibrary": "org.openx.data.jsonserde.JsonSerDe"}}}))
PY
)
if aws glue get-table --database-name branch --name raw_households >/dev/null 2>&1; then
  aws glue update-table --database-name branch --table-input "$TABLE" >/dev/null
else
  aws glue create-table --database-name branch --table-input "$TABLE" >/dev/null
fi
echo "table   branch.raw_households over s3://$BUCKET/branch/raw/households/"

# 3. The job script and the job.
aws s3 cp branch_receipts.py "s3://$BUCKET/branch/jobs/branch_receipts.py" --only-show-errors
CONF="spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions --conf spark.sql.catalog.glue_catalog=org.apache.iceberg.spark.SparkCatalog --conf spark.sql.catalog.glue_catalog.catalog-impl=org.apache.iceberg.aws.glue.GlueCatalog --conf spark.sql.catalog.glue_catalog.io-impl=org.apache.iceberg.aws.s3.S3FileIO --conf spark.sql.catalog.glue_catalog.warehouse=s3://$BUCKET/branch/tables/"
ARGS=$(python3 -c 'import json,sys; print(json.dumps({"--datalake-formats":"iceberg","--conf":sys.argv[1],"--BUCKET":sys.argv[2],"--DAY":sys.argv[3]}))' "$CONF" "$BUCKET" "$DAY")
JOBDEF=$(python3 -c 'import json,sys; print(json.dumps({"Role":sys.argv[1],"GlueVersion":"5.0","WorkerType":"G.1X","NumberOfWorkers":2,"Timeout":15,"MaxRetries":0,"Command":{"Name":"glueetl","ScriptLocation":sys.argv[2],"PythonVersion":"3"},"DefaultArguments":json.loads(sys.argv[3])}))' \
  "arn:aws:iam::$ACCOUNT:role/$ROLE" "s3://$BUCKET/branch/jobs/branch_receipts.py" "$ARGS")
if aws glue get-job --job-name "$JOB" >/dev/null 2>&1; then
  aws glue update-job --job-name "$JOB" --job-update "$JOBDEF" >/dev/null; echo "job     $JOB updated"
else
  aws glue create-job --name "$JOB" --cli-input-json "$JOBDEF" >/dev/null; echo "job     $JOB created"
fi
echo
echo "Next: the quick check in the assignment's Setup, then task 2 starts the job:"
echo "  aws glue start-job-run --job-name $JOB"
