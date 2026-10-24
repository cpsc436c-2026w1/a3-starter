#!/bin/bash
# Remove the quality gate: the trigger, the function, its role and its logs. Your scenarios and results in S3 stay.
set -uo pipefail
export AWS_DEFAULT_REGION=ca-central-1
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET=436c-glue-$ACCOUNT
T=$(mktemp)
aws s3api get-bucket-notification-configuration --bucket "$BUCKET" --output json > "$T" || {
  echo "STOP: could not read the bucket's notifications; nothing changed"; exit 1; }
python3 - "$T" <<'PY'
import json, sys
raw = open(sys.argv[1]).read().strip()
cfg = json.loads(raw) if raw else {}
cfg.pop("ResponseMetadata", None)
cfg["LambdaFunctionConfigurations"] = [c for c in cfg.get("LambdaFunctionConfigurations", []) if c.get("Id") != "quality-gate"]
json.dump(cfg, open(sys.argv[1], "w"))
PY
aws s3api put-bucket-notification-configuration --bucket "$BUCKET" --notification-configuration "file://$T" && echo "trigger removed"
aws lambda delete-function --function-name 436c-quality-gate && echo "function deleted"
aws iam delete-role-policy --role-name 436c-quality-gate --policy-name gate
aws iam detach-role-policy --role-name 436c-quality-gate --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam delete-role --role-name 436c-quality-gate && echo "role deleted"
aws logs delete-log-group --log-group-name /aws/lambda/436c-quality-gate && echo "log group deleted"
rm -f "$T"
