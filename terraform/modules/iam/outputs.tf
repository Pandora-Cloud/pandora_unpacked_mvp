# terraform/modules/iam/outputs.tf
output "lambda_exec_arn" {
  value = aws_iam_role.lambda_exec.arn
}

output "authenticated_role_arn" {
  value = aws_iam_role.authenticated_role.arn
}

output "unauthenticated_role_arn" {
  value = aws_iam_role.unauthenticated_role.arn
}