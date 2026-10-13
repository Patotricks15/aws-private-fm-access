# ─── Networking: VPC #1 — serverless application + customer database ────────

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "app" {
  cidr_block           = var.app_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-vpc"
  })
}

resource "aws_subnet" "app_private" {
  vpc_id            = aws_vpc.app.id
  cidr_block        = var.app_private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-private"
  })
}

resource "aws_route_table" "app_private" {
  vpc_id = aws_vpc.app.id

  # Traffic bound for VPC #2 (the foundation-model VPC) stays on the AWS
  # network backbone by routing over the private connection instead of an
  # internet gateway — this subnet has no route to 0.0.0.0/0 at all.
  route {
    cidr_block                = var.fm_vpc_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.app_to_fm.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-private-rt"
  })
}

resource "aws_route_table_association" "app_private" {
  subnet_id      = aws_subnet.app_private.id
  route_table_id = aws_route_table.app_private.id
}

# ─── Networking: VPC #2 — private access to foundation models ───────────────

resource "aws_vpc" "fm" {
  cidr_block           = var.fm_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-fm-vpc"
  })
}

resource "aws_subnet" "fm_private" {
  vpc_id            = aws_vpc.fm.id
  cidr_block        = var.fm_private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-fm-private"
  })
}

resource "aws_route_table" "fm_private" {
  vpc_id = aws_vpc.fm.id

  route {
    cidr_block                = var.app_vpc_cidr
    vpc_peering_connection_id = aws_vpc_peering_connection.app_to_fm.id
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-fm-private-rt"
  })
}

resource "aws_route_table_association" "fm_private" {
  subnet_id      = aws_subnet.fm_private.id
  route_table_id = aws_route_table.fm_private.id
}

# ─── Private connection: VPC peering stands in for the cross-VPC PrivateLink
# hop, since a local emulator cannot provision a real VPC Endpoint Service
# backed by a Network Load Balancer. The two interface endpoints below still
# model the PrivateLink entry/exit points on each side of this connection. ──

resource "aws_vpc_peering_connection" "app_to_fm" {
  vpc_id      = aws_vpc.app.id
  peer_vpc_id = aws_vpc.fm.id
  auto_accept = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-to-fm-private-connection"
  })
}

# ─── Security groups ─────────────────────────────────────────────────────────

resource "aws_security_group" "lambda" {
  name        = "${local.name_prefix}-lambda-sg"
  description = "Serverless application: egress only to the customer database and the private endpoint."
  vpc_id      = aws_vpc.app.id

  egress {
    description = "HTTPS to the endpoint governing private access to foundation models"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.app_vpc_cidr]
  }

  egress {
    description = "HTTPS to DynamoDB (customer database)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-lambda-sg"
  })
}

resource "aws_security_group" "app_endpoint" {
  name        = "${local.name_prefix}-app-endpoint-sg"
  description = "Endpoint: allow inbound HTTPS only from the serverless application."
  vpc_id      = aws_vpc.app.id

  ingress {
    description     = "HTTPS from the serverless application"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-endpoint-sg"
  })
}

resource "aws_security_group" "fm_endpoint" {
  name        = "${local.name_prefix}-fm-endpoint-sg"
  description = "Access FM models: allow inbound HTTPS only from VPC #1 over the private connection."
  vpc_id      = aws_vpc.fm.id

  ingress {
    description = "HTTPS routed from VPC #1 (the app VPC) over the private connection"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.app_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-fm-endpoint-sg"
  })
}

# ─── Endpoint (VPC #1): PrivateLink interface endpoint governed by a policy
# that restricts which principals/actions may use the private path into the
# foundation-model network. ───────────────────────────────────────────────────

resource "aws_vpc_endpoint" "app_access" {
  vpc_id              = aws_vpc.app.id
  service_name        = "com.amazonaws.${var.region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.app_private.id]
  security_group_ids  = [aws_security_group.app_endpoint.id]
  private_dns_enabled = false

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowServerlessApplicationOnly"
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.lambda_exec.arn }
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
      ]
      Resource = "*"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-app-endpoint"
  })
}

# ─── Access FM models (VPC #2): the VPC interface endpoint for the
# foundation-model service itself, reached by routing traffic over the
# private connection rather than the public internet. ────────────────────────

resource "aws_vpc_endpoint" "fm_access" {
  vpc_id              = aws_vpc.fm.id
  service_name        = "com.amazonaws.${var.region}.bedrock-runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.fm_private.id]
  security_group_ids  = [aws_security_group.fm_endpoint.id]
  private_dns_enabled = false

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowServerlessApplicationOnly"
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.lambda_exec.arn }
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
      ]
      Resource = "*"
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-fm-access-endpoint"
  })
}

# ─── Customer database (DynamoDB), private in VPC #1's subnet ───────────────

resource "aws_dynamodb_table" "customer_database" {
  name         = "${local.name_prefix}-${var.customer_database_table_name}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "customerId"

  attribute {
    name = "customerId"
    type = "S"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.customer_database_table_name}"
  })
}

resource "aws_dynamodb_table_item" "sample_customers" {
  for_each = {
    "cust-001" = { name = "Ada Lovelace", tier = "GOLD" }
    "cust-002" = { name = "Grace Hopper", tier = "SILVER" }
  }

  table_name = aws_dynamodb_table.customer_database.name
  hash_key   = aws_dynamodb_table.customer_database.hash_key

  item = jsonencode({
    customerId = { S = each.key }
    name       = { S = each.value.name }
    tier       = { S = each.value.tier }
  })
}

# ─── IAM role for the serverless application (Lambda) ───────────────────────

resource "aws_iam_role" "lambda_exec" {
  name = "${local.name_prefix}-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${local.name_prefix}-lambda-dynamodb"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:GetItem"]
      Resource = aws_dynamodb_table.customer_database.arn
    }]
  })
}

resource "aws_iam_role_policy" "lambda_bedrock" {
  name = "${local.name_prefix}-lambda-bedrock"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
      ]
      Resource = "arn:aws:bedrock:${var.region}::foundation-model/${var.bedrock_text_model_id}"
    }]
  })
}

# ─── Lambda package: serverless application ──────────────────────────────────

resource "null_resource" "lambda_package" {
  triggers = {
    handler_sha = filesha256("${path.module}/src/lambda/serverless_application/handler.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/build_lambda_package.sh ${path.module} serverless_application"
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda/serverless_application/handler.py"
  output_path = "${path.module}/.build/serverless_application.zip"

  depends_on = [null_resource.lambda_package]
}

# ─── Serverless application (Lambda), deployed inside VPC #1's private subnet

resource "aws_lambda_function" "serverless_application" {
  function_name = "${local.name_prefix}-serverless-application"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  vpc_config {
    subnet_ids         = [aws_subnet.app_private.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      REGION              = var.region
      CUSTOMER_TABLE_NAME = aws_dynamodb_table.customer_database.name
      TEXT_MODEL_ID       = var.bedrock_text_model_id
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-serverless-application"
  })

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy_attachment.lambda_vpc_access,
    aws_iam_role_policy.lambda_dynamodb,
    aws_iam_role_policy.lambda_bedrock,
    aws_vpc_endpoint.app_access,
    aws_vpc_endpoint.fm_access,
  ]
}
