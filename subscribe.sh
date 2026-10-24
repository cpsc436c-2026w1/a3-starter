#!/bin/bash
# In CloudShell, subscribe your email address to head office's replies for your account:
#   bash subscribe.sh you@example.com
# In the AWS Notifications email, click "Confirm subscription". You should see "Subscription confirmed".
set -euo pipefail
EMAIL=${1:?usage: bash subscribe.sh EMAIL}
TOPIC=arn:aws:sns:ca-central-1:940482406111:head-office-replies
ACC=$(aws sts get-caller-identity --query Account --output text)
echo "subscribing $EMAIL for account $ACC"
ATTRS=$(mktemp); trap 'rm -f "$ATTRS"' EXIT
printf '{"FilterPolicy":"{\\"account\\":[\\"%s\\"]}"}' "$ACC" > "$ATTRS"
aws sns subscribe --region ca-central-1 --topic-arn "$TOPIC" --protocol email --notification-endpoint "$EMAIL" \
  --attributes "file://$ATTRS" --query SubscriptionArn --output text
echo 'In the AWS Notifications email, click "Confirm subscription". You should see "Subscription confirmed".'
