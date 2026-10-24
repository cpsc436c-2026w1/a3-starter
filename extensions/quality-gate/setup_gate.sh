#!/bin/bash
# Quality gate setup: run once in CloudShell (Region ca-central-1), from this folder, after A3's setup.
#   bash setup_gate.sh
# 1. copies features/ (your scenarios and steps) to s3://436c-glue-<account>/branch/checks/features/
# 2. creates the role 436c-quality-gate (Athena queries, read branch/tables/, branch/checks/ and branch/raw/households/, write branch/checks/results/)
# 3. packages behave, the handler and ../iceberg-internals into the Lambda function 436c-quality-gate
# 4. makes every Iceberg commit under branch/tables/ (a new *.metadata.json) invoke the function
# After a change to features/ (scenarios or steps), step 1 is enough: bash setup_gate.sh features
set -euo pipefail
export AWS_DEFAULT_REGION=ca-central-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET=436c-glue-$ACCOUNT
FN=436c-quality-gate
ROLE=436c-quality-gate
HERE=$(cd "$(dirname "$0")" && pwd)
RESULTS=$(aws athena get-work-group --work-group primary --query 'WorkGroup.Configuration.ResultConfiguration.OutputLocation' --output text)
RBUCKET=$(echo "$RESULTS" | sed -E 's|s3://([^/]+)/.*|\1|')
[ -n "$RBUCKET" ] && [ "$RBUCKET" != "None" ] || { echo "STOP: workgroup primary has no result location; run tutorial 1's setup_athena.sh"; exit 1; }

aws s3 sync "$HERE/features/" "s3://$BUCKET/branch/checks/features/" --delete --exclude "*.pyc" --exclude "__pycache__/*" --only-show-errors
echo "features s3://$BUCKET/branch/checks/features/"
[ "${1:-}" = "features" ] && exit 0

if ! aws iam get-role --role-name "$ROLE" >/dev/null 2>&1; then
  aws iam create-role --role-name "$ROLE" --description "CPSC 436C A3 quality gate" --assume-role-policy-document \
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "$ROLE" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  NEW_ROLE=1
fi
# read-only on branch/tables/ and no glue:UpdateTable: this is what stops a scenario from committing and triggering itself
aws iam put-role-policy --role-name "$ROLE" --policy-name gate --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[
 {\"Effect\":\"Allow\",\"Action\":[\"athena:StartQueryExecution\",\"athena:GetQueryExecution\",\"athena:GetQueryResults\"],\"Resource\":\"arn:aws:athena:ca-central-1:$ACCOUNT:workgroup/primary\"},
 {\"Effect\":\"Allow\",\"Action\":[\"glue:GetDatabase\",\"glue:GetDatabases\",\"glue:GetTable\",\"glue:GetTables\",\"glue:GetPartitions\"],\"Resource\":[\"arn:aws:glue:ca-central-1:$ACCOUNT:catalog\",\"arn:aws:glue:ca-central-1:$ACCOUNT:database/branch\",\"arn:aws:glue:ca-central-1:$ACCOUNT:table/branch/*\"]},
 {\"Effect\":\"Allow\",\"Action\":[\"s3:ListBucket\",\"s3:GetBucketLocation\"],\"Resource\":\"arn:aws:s3:::$BUCKET\"},
 {\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":[\"arn:aws:s3:::$BUCKET/branch/tables/*\",\"arn:aws:s3:::$BUCKET/branch/checks/*\",\"arn:aws:s3:::$BUCKET/branch/raw/households/*\"]},
 {\"Effect\":\"Allow\",\"Action\":\"s3:PutObject\",\"Resource\":\"arn:aws:s3:::$BUCKET/branch/checks/results/*\"},
 {\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\",\"s3:ListBucket\",\"s3:GetBucketLocation\",\"s3:AbortMultipartUpload\"],\"Resource\":[\"arn:aws:s3:::$RBUCKET\",\"arn:aws:s3:::$RBUCKET/*\"]}]}"
echo "role     $ROLE"

BUILD=$(mktemp -d); trap 'rm -rf "$BUILD"' EXIT
python3 -m pip install --quiet --target "$BUILD" --python-version 3.12 --implementation cp --only-binary=:all: behave==1.3.3
cp "$HERE/handler.py" "$BUILD/"; cp -r "$HERE/../iceberg-internals" "$BUILD/iceberg-internals"
(cd "$BUILD" && python3 -c "import zipfile,os
z=zipfile.ZipFile('/tmp/436c-gate.zip','w',zipfile.ZIP_DEFLATED)
for r,_,fs in os.walk('.'):
    for f in fs:
        if '__pycache__' not in r: z.write(os.path.join(r,f))
z.close()")
if aws lambda get-function --function-name "$FN" >/dev/null 2>&1; then
  aws lambda update-function-code --function-name "$FN" --zip-file fileb:///tmp/436c-gate.zip >/dev/null
  echo "function $FN updated"
else
  [ -n "${NEW_ROLE:-}" ] && { echo "waiting 15 s for the new role"; sleep 15; }
  for i in 1 2 3 4; do
    aws lambda create-function --function-name "$FN" --runtime python3.12 --handler handler.handler --timeout 300 \
      --memory-size 512 --role "arn:aws:iam::$ACCOUNT:role/$ROLE" --zip-file fileb:///tmp/436c-gate.zip \
      --environment "Variables={WORKGROUP=primary}" >/dev/null 2>/tmp/436c-gate-err && break
    echo "role not ready yet, retrying in 10 s"; sleep 10
  done
  [ -s /tmp/436c-gate-err ] && cat /tmp/436c-gate-err
  aws lambda wait function-active-v2 --function-name "$FN"
  echo "function $FN created"
fi
# one run at a time: a burst of commits queues instead of competing with your own Athena queries
aws lambda put-function-concurrency --function-name "$FN" --reserved-concurrent-executions 1 >/dev/null 2>&1 \
  || echo "note: this account cannot reserve concurrency; commits close together may run the gate at the same time"
aws logs create-log-group --log-group-name "/aws/lambda/$FN" 2>/dev/null || true
aws logs put-retention-policy --log-group-name "/aws/lambda/$FN" --retention-in-days 14

aws lambda add-permission --function-name "$FN" --statement-id s3-commits --action lambda:InvokeFunction \
  --principal s3.amazonaws.com --source-arn "arn:aws:s3:::$BUCKET" --source-account "$ACCOUNT" >/dev/null 2>&1 || true
ARN=$(aws lambda get-function --function-name "$FN" --query Configuration.FunctionArn --output text)
# keep any notifications the bucket already has; add (or replace) ours
aws s3api get-bucket-notification-configuration --bucket "$BUCKET" --output json > "$BUILD/notif.json"
python3 - "$BUILD/notif.json" "$ARN" <<'PY'
import json, sys
path, arn = sys.argv[1], sys.argv[2]
raw = open(path).read().strip()
cfg = json.loads(raw) if raw else {}
cfg.pop("ResponseMetadata", None)
lam = [c for c in cfg.get("LambdaFunctionConfigurations", []) if c.get("Id") != "quality-gate"]
lam.append({"Id": "quality-gate", "LambdaFunctionArn": arn, "Events": ["s3:ObjectCreated:*"],
            "Filter": {"Key": {"FilterRules": [{"Name": "prefix", "Value": "branch/tables/"}, {"Name": "suffix", "Value": ".metadata.json"}]}}})
cfg["LambdaFunctionConfigurations"] = lam
json.dump(cfg, open(path, "w"))
PY
aws s3api put-bucket-notification-configuration --bucket "$BUCKET" --notification-configuration "file://$BUILD/notif.json"
echo "trigger  every new branch/tables/**/*.metadata.json -> $FN"
echo
echo "Test it: commit to a branch table, for example in Athena"
echo "  ALTER TABLE branch.members SET TBLPROPERTIES ('vacuum_min_snapshots_to_keep' = '2')"
echo "  (the next time, '1', the default: setting the value a table already has is no commit)"
echo "then, a minute later:  aws s3 ls s3://$BUCKET/branch/checks/results/ --recursive"
echo "No result after two minutes:  aws logs tail /aws/lambda/$FN --since 10m"
