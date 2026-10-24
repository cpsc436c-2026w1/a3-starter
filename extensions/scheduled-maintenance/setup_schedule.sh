#!/bin/bash
# Scheduled maintenance: run once in CloudShell (Region ca-central-1), from this folder, after A3's task 4.
#   bash setup_schedule.sh          nightly OPTIMIZE (02:00) and VACUUM (02:30), Vancouver time, on the three tables
#   bash setup_schedule.sh --now    the same statements once, starting in about 3 minutes, to test the setup
# EventBridge Scheduler calls Athena's StartQueryExecution directly (no Lambda); the role 436c-maintenance lets it
# run those statements on your tables. Each statement is its own schedule, because Athena runs one statement per call.
set -euo pipefail
export AWS_DEFAULT_REGION=ca-central-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET=436c-glue-$ACCOUNT
ROLE=436c-maintenance
GROUP=436c-maintenance
TABLES=${TABLES:-"members receipts price_events"}
RESULTS=$(aws athena get-work-group --work-group primary --query 'WorkGroup.Configuration.ResultConfiguration.OutputLocation' --output text)
RBUCKET=$(echo "$RESULTS" | sed -E 's|s3://([^/]+)/.*|\1|')
[ -n "$RBUCKET" ] && [ "$RBUCKET" != "None" ] || { echo "STOP: workgroup primary has no result location; run tutorial 1's setup_athena.sh"; exit 1; }

if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" --description "CPSC 436C A3 scheduled maintenance" --assume-role-policy-document \
    "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"scheduler.amazonaws.com\"},\"Action\":\"sts:AssumeRole\",\"Condition\":{\"StringEquals\":{\"aws:SourceAccount\":\"$ACCOUNT\"}}}]}" >/dev/null
  echo "waiting 15 s for the new role"; sleep 15
fi
aws iam put-role-policy --role-name "$ROLE" --policy-name maintenance --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[
 {\"Effect\":\"Allow\",\"Action\":[\"athena:StartQueryExecution\",\"athena:GetQueryExecution\"],\"Resource\":\"arn:aws:athena:ca-central-1:$ACCOUNT:workgroup/primary\"},
 {\"Effect\":\"Allow\",\"Action\":[\"glue:GetDatabase\",\"glue:GetTable\",\"glue:GetTables\",\"glue:UpdateTable\",\"glue:GetPartitions\"],\"Resource\":[\"arn:aws:glue:ca-central-1:$ACCOUNT:catalog\",\"arn:aws:glue:ca-central-1:$ACCOUNT:database/branch\",\"arn:aws:glue:ca-central-1:$ACCOUNT:table/branch/*\"]},
 {\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"s3:DeleteObject\",\"s3:ListBucket\",\"s3:GetBucketLocation\",\"s3:AbortMultipartUpload\"],\"Resource\":[\"arn:aws:s3:::$BUCKET\",\"arn:aws:s3:::$BUCKET/branch/tables/*\"]},
 {\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"s3:ListBucket\",\"s3:GetBucketLocation\",\"s3:AbortMultipartUpload\"],\"Resource\":[\"arn:aws:s3:::$RBUCKET\",\"arn:aws:s3:::$RBUCKET/*\"]}]}"
echo "role     $ROLE"
aws scheduler get-schedule-group --name "$GROUP" >/dev/null 2>&1 || aws scheduler create-schedule-group --name "$GROUP" >/dev/null

ROLE_ARN=arn:aws:iam::$ACCOUNT:role/$ROLE
if [ "${1:-}" = "--now" ]; then
  T1=$(date -u -d '+3 min' +%Y-%m-%dT%H:%M:%S); T2=$(date -u -d '+5 min' +%Y-%m-%dT%H:%M:%S)
  OPT="at($T1)"; VAC="at($T2)"; TZ_ARG=UTC; AFTER=DELETE; PREFIX=now-; END=()
  echo "one-time run: OPTIMIZE at $T1 UTC, VACUUM at $T2 UTC"
else
  # nightly for 30 days, then the schedules stop by themselves (teardown_schedule.sh removes them earlier)
  OPT="cron(0 2 * * ? *)"; VAC="cron(30 2 * * ? *)"; TZ_ARG=America/Vancouver; AFTER=NONE; PREFIX=
  END=(--end-date "$(date -u -d '+30 days' +%Y-%m-%dT%H:%M:%SZ)")
fi
for t in $TABLES; do
  for op in optimize vacuum; do
    if [ $op = optimize ]; then SQL="OPTIMIZE branch.$t REWRITE DATA USING BIN_PACK"; EXPR=$OPT; else SQL="VACUUM branch.$t"; EXPR=$VAC; fi
    NAME="$PREFIX$op-$t"   # one-time runs are now-…, so testing never replaces the nightly schedules
    INPUT=$(python3 -c 'import json,sys; print(json.dumps({"QueryString": sys.argv[1], "WorkGroup": "primary"}))' "$SQL")
    TARGET=$(python3 -c 'import json,sys; print(json.dumps({"Arn": "arn:aws:scheduler:::aws-sdk:athena:startQueryExecution", "RoleArn": sys.argv[1], "Input": sys.argv[2], "RetryPolicy": {"MaximumRetryAttempts": 2}}))' "$ROLE_ARN" "$INPUT")
    aws scheduler delete-schedule --name "$NAME" --group-name "$GROUP" >/dev/null 2>&1 || true
    aws scheduler create-schedule --name "$NAME" --group-name "$GROUP" --schedule-expression "$EXPR" \
      --schedule-expression-timezone "$TZ_ARG" --flexible-time-window Mode=OFF --target "$TARGET" \
      --action-after-completion "$AFTER" "${END[@]}" >/dev/null
    echo "schedule $GROUP/$NAME  $EXPR  $SQL"
  done
done
echo
echo "Check the runs in Athena's Recent queries (they run as the role $ROLE), or:"
echo "  aws athena list-query-executions --work-group primary --max-items 6"
