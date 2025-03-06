# terraform/modules/iam/main.tf

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = "arn:aws:dynamodb:${var.region}:*:table/${var.dynamodb_table}"
      },
      {
        Effect = "Allow"
        Action = "bedrock:InvokeModel"
        Resource = "arn:aws:bedrock:${var.region}::foundation-model/amazon.titan-text-*"
      },
      {
        Effect = "Allow"
        Action = "ssm:GetParameter"
        Resource = "arn:aws:ssm:${var.region}:*:parameter/${var.project_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "sqs:SendMessage"
        Resource = var.dlq_arn
      },
      {
        Effect = "Allow"
        Action = "xray:PutTraceSegments"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "authenticated_role" {
  name = "${var.project_name}-authenticated-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = "cognito-identity.amazonaws.com"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "cognito-identity.amazonaws.com:aud" = module.auth.identity_pool_id
        }
        "ForAnyValue:StringLike" = {
          "cognito-identity.amazonaws.com:amr" = "authenticated"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "authenticated_policy" {
  role = aws_iam_role.authenticated_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-identity:*",
          "cognito-idp:*"
        ]
        Resource = "*"
      }
    ]
  })
}
