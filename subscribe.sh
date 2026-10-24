#!/bin/bash
# Subscribe an email address to head office's replies for ONE branch account.
#   bash subscribe.sh you@example.com            uses the profile whose account is 322614675581 (found automatically)
#   bash subscribe.sh you@example.com myprofile  uses that profile
#   ACCOUNT=123456789012 bash subscribe.sh you@example.com   look for that account instead
# Students run it in CloudShell in their own account (no profile needed: CloudShell's default is their account).
set -euo pipefail
EMAIL=${1:?usage: bash subscribe.sh EMAIL [PROFILE]}
WANT=${ACCOUNT:-322614675581}
TOPIC=arn:aws:sns:ca-central-1:940482406111:head-office-replies

if [ -n "${2:-}" ]; then PROFILE_ARGS=(--profile "$2")
elif [ -n "${AWS_EXECUTION_ENV:-}" ]; then PROFILE_ARGS=()          # CloudShell
else
  PROFILE_ARGS=()
  for p in $(aws configure list-profiles); do
    a=$(aws sts get-caller-identity --profile "$p" --query Account --output text 2>/dev/null || true)
    if [ "$a" = "$WANT" ]; then PROFILE_ARGS=(--profile "$p"); echo "using profile $p (account $a)"; break; fi
  done
  [ ${#PROFILE_ARGS[@]} -gt 0 ] || { echo "No profile reaches account $WANT. Sign in (aws sso login --profile <p>) or pass a profile name."; exit 1; }
fi

ACC=$(aws sts get-caller-identity "${PROFILE_ARGS[@]}" --query Account --output text)
echo "subscribing $EMAIL for account $ACC"
ATTRS=$(mktemp); trap 'rm -f "$ATTRS"' EXIT
printf '{"FilterPolicy":"{\\"account\\":[\\"%s\\"]}"}' "$ACC" > "$ATTRS"
aws sns subscribe "${PROFILE_ARGS[@]}" --region ca-central-1 --topic-arn "$TOPIC" \
  --protocol email --notification-endpoint "$EMAIL" --attributes "file://$ATTRS" --query SubscriptionArn --output text
echo "Now open the email from AWS Notifications and click Confirm subscription."
