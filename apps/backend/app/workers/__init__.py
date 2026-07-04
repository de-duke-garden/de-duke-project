"""Background Task Processor jobs -- consumed from the SQS Task Queue,
run as a separate Fargate worker pool scaled on queue depth, never sharing
compute with the Backend API Service (architecture.md)."""
