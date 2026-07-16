# De-Duke — Web Application Firewall module
# Sits in front of the Application Load Balancer (architecture.md, Security):
# baseline protection against common web exploits and bot traffic, plus
# per-IP rate limiting on sensitive paths (auth, search, chat).

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.environment}-de-duke-waf"
  description = "Baseline WAF for De-Duke Backend API Service ALB"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "aws-managed-common-rule-set"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # SizeRestrictions_BODY blocks (not just skips inspecting) any
        # request body exceeding the WAF's inspection size limit. For a
        # REGIONAL/ALB-scoped web ACL that limit is a HARD, non-configurable
        # 8 KB -- unlike CloudFront/API Gateway/AppSync, `association_config`
        # cannot raise this for ALB, so there is no way to make WAF inspect
        # (and thus not body-size-block) a full multipart image upload here.
        # Every profile-photo/host-verification-document upload
        # (FEAT-002's /v1/host-accounts, FEAT-004/005's listing photos) is
        # far larger than 8 KB and was being blocked outright at the edge --
        # confirmed via wafv2 get-sampled-requests showing
        # Action=BLOCK/RuleNameWithinRuleGroup=SizeRestrictions_BODY for
        # POST /v1/host-accounts -- before the request ever reached the
        # ALB's target group, let alone the Backend API Service (which is
        # why zero POST /v1/host-accounts entries ever appeared in
        # CloudWatch despite repeated reported submission failures: the
        # backend never saw the request to log). Overriding this specific
        # rule to Count (not disabling the whole managed rule group) is
        # AWS's documented pattern for file-upload endpoints behind CRS on
        # an ALB: every other AWSManagedRulesCommonRuleSet protection stays
        # active, and WAF still inspects the first 8 KB of any body under
        # every rule; the backend's own request size/content-type
        # validation (FastAPI/Pydantic on multipart form fields) remains
        # the actual enforcement point for oversized or malformed uploads.
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-managed-known-bad-inputs"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Centralized rate limit on sensitive endpoints (auth/search/chat) — actual
  # per-user/per-IP counters live in the Redis Caching Layer application-side
  # (architecture.md); this WAF rule is a coarse edge-level backstop.
  rule {
    name     = "rate-limit-per-ip"
    priority = 3
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.rate_limit_per_5min
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.environment}-de-duke-waf"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}
