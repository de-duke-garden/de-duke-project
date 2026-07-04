# Security groups are created here at the root -- not inside the fargate
# module -- specifically to avoid a dependency cycle: RDS/Redis need to
# allow ingress from the backend service's security group, while the backend
# service (via the fargate module) needs the RDS/Redis secret ARNs as
# container secrets. Defining both groups up front breaks that cycle.

resource "aws_security_group" "alb" {
  name_prefix = "${var.environment}-de-duke-alb-"
  vpc_id      = module.networking.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_security_group" "backend_service" {
  name_prefix = "${var.environment}-de-duke-api-"
  vpc_id      = module.networking.vpc_id

  ingress {
    description     = "From ALB"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}
