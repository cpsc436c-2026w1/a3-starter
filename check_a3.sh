#!/bin/bash
# A3 check: run in CloudShell (Region ca-central-1) before you start A3, after Setup, or whenever a step fails.
#   curl -sL ilm.wiki/436c/a3-check | bash
# It only reads your account and changes nothing. Each line says ✔ or ✗, and each ✗ says what to run.
export AWS_DEFAULT_REGION=ca-central-1
FAIL=0
ok()  { echo "✔ $1"; }
bad() { echo "✗ $1"; echo "    fix: $2"; FAIL=$((FAIL + 1)); }

ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ -z "$ACCOUNT" ]; then
  echo "✗ CloudShell cannot read your account. Reopen CloudShell from the AWS console and run this again."; exit 1
fi
ok "account $ACCOUNT, Region ca-central-1"
BUCKET=436c-glue-$ACCOUNT

GLUE="curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/l7-spark-glue/main/setup_glue.sh && bash setup_glue.sh"
ATHENA="curl -fsSO https://raw.githubusercontent.com/cpsc436c-2026w1/b3-t1-athena-rides/main/setup_athena.sh && bash setup_athena.sh"
LIMIT10="aws athena update-work-group --work-group primary --configuration-updates BytesScannedCutoffPerQuery=10000000000"
SHELF="aws athena create-data-catalog --name shelf --type LAMBDA --parameters function=arn:aws:lambda:ca-central-1:940482406111:function:436c-ddb-connector"
SETUP="in the a3-starter folder, run: bash setup_a3.sh"

# Earlier setups (the Glue tutorial and the Athena tutorial)
aws iam get-role --role-name 436c-glue-notebook >/dev/null 2>&1 \
  && ok "Glue role 436c-glue-notebook (Glue tutorial setup)" || bad "no Glue role 436c-glue-notebook" "$GLUE"
aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1 \
  && ok "bucket $BUCKET (Glue tutorial setup)" || bad "no bucket $BUCKET" "$GLUE"
aws athena get-data-catalog --name course >/dev/null 2>&1 \
  && ok "Athena data source course (Athena tutorial setup)" || bad "no Athena data source course" "$ATHENA"
LOC=$(aws athena get-work-group --work-group primary --query 'WorkGroup.Configuration.ResultConfiguration.OutputLocation' --output text 2>/dev/null)
case "$LOC" in s3://*) ok "Athena saves results to $LOC (Athena tutorial setup)";; *) bad "Athena has no result location" "$ATHENA";; esac

# A3 Setup steps 0 to 3
LIMIT=$(aws athena get-work-group --work-group primary --query 'WorkGroup.Configuration.BytesScannedCutoffPerQuery' --output text 2>/dev/null)
case "$LIMIT" in
  ""|None) bad "no Data scanned limit on the workgroup primary (Setup step 0)" "$LIMIT10" ;;
  *) if [ "$LIMIT" -ge 10000000000 ]; then ok "Data scanned limit $((LIMIT / 1000000000)) GB a query (Setup step 0)"
     else bad "Data scanned limit is $((LIMIT / 1000000000)) GB, too low for task 1's report (Setup step 0)" "$LIMIT10"; fi ;;
esac
aws athena get-data-catalog --name shelf >/dev/null 2>&1 \
  && ok "Athena data source shelf (Setup step 2)" || bad "no Athena data source shelf" "$SHELF"
aws s3api head-object --bucket "$BUCKET" --key branch/raw/_files.json >/dev/null 2>&1 \
  && ok "raw zone s3://$BUCKET/branch/raw/ (Setup step 3)" || bad "the raw zone is not in your bucket" "$SETUP"
aws glue get-database --name branch >/dev/null 2>&1 \
  && ok "Glue database branch (Setup step 3)" || bad "no Glue database branch" "$SETUP"
aws glue get-table --database-name branch --name raw_households >/dev/null 2>&1 \
  && ok "table branch.raw_households (Setup step 3)" || bad "no table branch.raw_households" "$SETUP"
if aws glue get-job --job-name branch-receipts >/dev/null 2>&1; then
  ok "Glue job branch-receipts (Setup step 3)"
  RUN=$(aws glue get-job-runs --job-name branch-receipts --max-items 1 --query 'JobRuns[0].[JobRunState,ErrorMessage]' --output text 2>/dev/null | head -1)
  case "$RUN" in
    ""|None*) echo "· branch-receipts has not run yet. Task 2.1 starts it." ;;
    SUCCEEDED*) ok "last run of branch-receipts succeeded" ;;
    RUNNING*|STARTING*|WAITING*) echo "· branch-receipts is still running. Wait for Succeeded before you query branch.receipts." ;;
    *) bad "last run of branch-receipts: $RUN" "read the error in the Glue console (ETL jobs, branch-receipts, Runs), then start the job again" ;;
  esac
else
  bad "no Glue job branch-receipts" "$SETUP"
fi
echo "· head office's email replies (Setup step 4) can't be checked from your account. Look for AWS's confirmation email."

echo
if [ "$FAIL" -eq 0 ]; then echo "All checks passed."; else echo "$FAIL check(s) failed. Run each fix above, then run this check again."; fi
