terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# S3 Bucket for static website hosting
resource "aws_s3_bucket" "website" {
  bucket = var.bucket_name

  tags = {
    Name        = "Resume Website"
    Environment = "production"
    Project     = "resume-challenge"
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 bucket ownership controls
resource "aws_s3_bucket_ownership_controls" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# S3 bucket policy for public read access
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.website]
}

# S3 website configuration
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# DynamoDB table for visitor counter
resource "aws_dynamodb_table" "visitor_counter" {
  name           = "${var.project_name}-visitor-counter"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "Visitor Counter"
    Environment = "production"
    Project     = var.project_name
  }
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "Lambda Role"
    Environment = "production"
    Project     = var.project_name
  }
}

# IAM policy for Lambda to access DynamoDB
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "${var.project_name}-lambda-dynamodb-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.visitor_counter.arn
      }
    ]
  })
}

# IAM policy for Lambda CloudWatch logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function for visitor counter
resource "aws_lambda_function" "visitor_counter" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.project_name}-visitor-counter"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "nodejs18.x"
  timeout         = 30
  memory_size     = 128

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visitor_counter.name
    }
  }

  tags = {
    Name        = "Visitor Counter Lambda"
    Environment = "production"
    Project     = var.project_name
  }
}

# Create ZIP file for Lambda
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "visitor_api" {
  name = "${var.project_name}-visitor-api"

  tags = {
    Name        = "Visitor API"
    Environment = "production"
    Project     = var.project_name
  }
}

# API Gateway resource
resource "aws_api_gateway_resource" "visitor_resource" {
  rest_api_id = aws_api_gateway_rest_api.visitor_api.id
  parent_id   = aws_api_gateway_rest_api.visitor_api.root_resource_id
  path_part   = "visitor-count"
}

# API Gateway method
resource "aws_api_gateway_method" "visitor_method" {
  rest_api_id   = aws_api_gateway_rest_api.visitor_api.id
  resource_id   = aws_api_gateway_resource.visitor_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# API Gateway integration
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.visitor_api.id
  resource_id = aws_api_gateway_resource.visitor_resource.id
  http_method = aws_api_gateway_method.visitor_method.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.visitor_counter.invoke_arn
}

# Lambda permission for API Gateway
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.visitor_api.execution_arn}/*/*"
}

# API Gateway deployment
resource "aws_api_gateway_deployment" "visitor_deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
  ]

  rest_api_id = aws_api_gateway_rest_api.visitor_api.id
  stage_name  = "prod"

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "website" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.website.website_endpoint
    origin_id   = "S3-${aws_s3_bucket.website.bucket}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  aliases = var.domain_name != "" ? [var.domain_name] : []

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.website.bucket}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = var.domain_name != "" ? aws_acm_certificate.website[0].arn : null
    ssl_support_method  = var.domain_name != "" ? "sni-only" : null
    cloudfront_default_certificate = var.domain_name == "" ? true : null
  }

  tags = {
    Name        = "Website CDN"
    Environment = "production"
    Project     = var.project_name
  }
}

# ACM certificate (only if domain is provided)
resource "aws_acm_certificate" "website" {
  count           = var.domain_name != "" ? 1 : 0
  provider        = aws.us-east-1
  domain_name     = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "Website Certificate"
    Environment = "production"
    Project     = var.project_name
  }
}

# Route 53 zone (if creating new zone)
resource "aws_route53_zone" "website" {
  count = var.domain_name != "" && var.create_route53_zone ? 1 : 0
  name  = var.domain_name

  tags = {
    Name        = "Website Zone"
    Environment = "production"
    Project     = var.project_name
  }
}

# Route 53 record
resource "aws_route53_record" "website" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = var.create_route53_zone ? aws_route53_zone.website[0].zone_id : data.aws_route53_zone.existing[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

# Data source for existing Route 53 zone
data "aws_route53_zone" "existing" {
  count = var.domain_name != "" && !var.create_route53_zone ? 1 : 0
  name  = var.domain_name
}

# S3 objects for website files
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  source       = "${path.module}/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/index.html")

  tags = {
    Name        = "Index HTML"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_s3_object" "css_file" {
  bucket       = aws_s3_bucket.website.id
  key          = "assets/index-Bt5BNpaL.css"
  source       = "${path.module}/assets/index-Bt5BNpaL.css"
  content_type = "text/css"
  etag         = filemd5("${path.module}/assets/index-Bt5BNpaL.css")

  tags = {
    Name        = "CSS File"
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_s3_object" "js_file" {
  bucket       = aws_s3_bucket.website.id
  key          = "assets/index-C0whrqCj.js"
  source       = "${path.module}/assets/index-C0whrqCj.js"
  content_type = "application/javascript"
  etag         = filemd5("${path.module}/assets/index-C0whrqCj.js")

  tags = {
    Name        = "JS File"
    Environment = "production"
    Project     = var.project_name
  }
}

# Additional provider for ACM certificate (must be in us-east-1)
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}


 