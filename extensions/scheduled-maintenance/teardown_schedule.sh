#!/bin/bash
# Remove the scheduled maintenance: every schedule in the group, the group and the role.
set -uo pipefail
export AWS_DEFAULT_REGION=ca-central-1
GROUP=436c-maintenance
for n in $(aws scheduler list-schedules --group-name "$GROUP" --query 'Schedules[].Name' --output text 2>/dev/null); do
  aws scheduler delete-schedule --name "$n" --group-name "$GROUP" && echo "deleted $n"
done
aws scheduler delete-schedule-group --name "$GROUP" 2>/dev/null && echo "group deleted"
aws iam delete-role-policy --role-name 436c-maintenance --policy-name maintenance
aws iam delete-role --role-name 436c-maintenance && echo "role deleted"
