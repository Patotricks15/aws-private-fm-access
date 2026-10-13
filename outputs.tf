output "lambda_function_name" {
  description = "Name of the serverless application Lambda function."
  value       = aws_lambda_function.serverless_application.function_name
}

output "customer_database_table_name" {
  description = "Name of the DynamoDB customer database table."
  value       = aws_dynamodb_table.customer_database.name
}

output "app_vpc_id" {
  description = "ID of VPC #1, which hosts the serverless application and the customer database."
  value       = aws_vpc.app.id
}

output "fm_vpc_id" {
  description = "ID of VPC #2, which hosts the private access path to foundation models."
  value       = aws_vpc.fm.id
}

output "private_connection_id" {
  description = "ID of the VPC peering connection modeling the private cross-VPC PrivateLink hop."
  value       = aws_vpc_peering_connection.app_to_fm.id
}

output "app_endpoint_id" {
  description = "ID of the policy-governed VPC interface endpoint in VPC #1."
  value       = aws_vpc_endpoint.app_access.id
}

output "fm_access_endpoint_id" {
  description = "ID of the VPC interface endpoint used to access foundation models in VPC #2."
  value       = aws_vpc_endpoint.fm_access.id
}
