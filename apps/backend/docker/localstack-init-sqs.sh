#!/bin/sh
# Runs automatically via LocalStack's init-hook mechanism (mounted to
# /etc/localstack/init/ready.d/ in docker-compose.yml, executed once
# LocalStack itself is ready) -- creates the same Task Queue + DLQ pair
# infra/modules/sqs/main.tf provisions in every real AWS environment
# (development-de-duke-tasks / development-de-duke-tasks-dlq), so local
# development exercises the same queue/DLQ/redrive shape as production.
set -e

DLQ_NAME="local-de-duke-tasks-dlq"
QUEUE_NAME="local-de-duke-tasks"

DLQ_URL=$(awslocal sqs create-queue --queue-name "$DLQ_NAME" --query "QueueUrl" --output text)
DLQ_ARN=$(awslocal sqs get-queue-attributes --queue-url "$DLQ_URL" --attribute-names QueueArn --query "Attributes.QueueArn" --output text)

# The AWS CLI's --attributes shorthand parser chokes on a hand-escaped JSON
# string passed inline (its KEY=VALUE splitter trips on the embedded
# quotes) -- writing the attributes as a real JSON file and passing
# --cli-input-json avoids that shorthand-syntax parsing entirely.
# maxReceiveCount=5 matches infra/modules/sqs/variables.tf's default --
# keep these in sync if that default ever changes.
cat > /tmp/create-queue.json <<EOF
{
  "QueueName": "${QUEUE_NAME}",
  "Attributes": {
    "RedrivePolicy": "{\"deadLetterTargetArn\":\"${DLQ_ARN}\",\"maxReceiveCount\":5}"
  }
}
EOF

QUEUE_URL=$(awslocal sqs create-queue --cli-input-json file:///tmp/create-queue.json --query "QueueUrl" --output text)

echo "LocalStack SQS ready: ${QUEUE_NAME} (DLQ: ${DLQ_NAME})"
echo "Queue URL: ${QUEUE_URL}"
