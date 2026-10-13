variable "project_name" {
  description = "Project name used as prefix for all resources."
  type        = string
  default     = "floci-private-fm-access"
}

variable "region" {
  description = "AWS region (simulated by floci)."
  type        = string
  default     = "us-east-1"
}

# ─── VPC #1: hosts the serverless application and the customer database ─────

variable "app_vpc_cidr" {
  description = "CIDR block for VPC #1, which hosts the serverless application."
  type        = string
  default     = "10.0.0.0/16"
}

variable "app_private_subnet_cidr" {
  description = "CIDR block for the private subnet in VPC #1."
  type        = string
  default     = "10.0.1.0/24"
}

# ─── VPC #2: hosts the private, internet-free path to foundation models ─────

variable "fm_vpc_cidr" {
  description = "CIDR block for VPC #2, which hosts the foundation-model access endpoint."
  type        = string
  default     = "10.1.0.0/16"
}

variable "fm_private_subnet_cidr" {
  description = "CIDR block for the private subnet in VPC #2."
  type        = string
  default     = "10.1.1.0/24"
}

variable "customer_database_table_name" {
  description = "Name of the DynamoDB table used as the private customer database."
  type        = string
  default     = "customer-database"
}

variable "bedrock_text_model_id" {
  description = "Bedrock foundation model id invoked privately from inside the VPC."
  type        = string
  default     = "amazon.titan-text-express-v1"
}
