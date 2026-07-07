#!/bin/sh
# Runs automatically via LocalStack's init-hook mechanism (mounted to
# /etc/localstack/init/ready.d/ in docker-compose.yml) -- creates the media
# bucket matching infra/modules/s3_cdn's real bucket, so local development
# exercises the same File Storage Service shape as production.
#
# Unlike the real bucket (private, served only via CloudFront's Origin
# Access Control -- see infra/modules/s3_cdn/main.tf), this bucket is left
# at LocalStack's default permissive access: LocalStack Community doesn't
# enforce S3 bucket policies/ACLs the way real AWS does, and there's no
# local CloudFront equivalent to front it anyway (see storage.py's
# build_media_url fallback). This is fine for local development -- never
# mirror "no access control" back into the real Terraform module.
set -e

BUCKET_NAME="local-de-duke-media"

awslocal s3 mb "s3://${BUCKET_NAME}"

echo "LocalStack S3 ready: ${BUCKET_NAME}"
