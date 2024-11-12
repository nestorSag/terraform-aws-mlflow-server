
variable "vpc_cidr_block" {
    description = "VPC CIDR block"
    type        = string
}

variable "vpc_private_subnets" {
    description = "VPC private subnets"
    type        = list(string)
}

variable "vpc_public_subnets" {
    description = "VPC public subnets"
    type        = list(string)
}

variable "vpc_db_subnets" {
    description = "VPC database subnets"
    type        = list(string)
}

variable "vpn_cidr_block" {
    description = "VPN CIDR block"
    type        = string
}

variable "vpn_clients" {
    description = "VPN client names (one per .ovpn file)"
    type        = list(string)
}

variable "db_instance_class" {
    description = "Database instance class"
    type        = string
}

variable "db_allocated_storage" {
    description = "Database allocated storage"
    type        = number
}

variable "db_name" {
    description = "Database name"
    type        = string
}

variable "db_username" {
    description = "Database username"
    type        = string
}

variable "db_port" {
    description = "Database port"
    type        = string
}

variable "db_deletion_protection" {
    description = "Database deletion protection"
    type        = bool
}

variable "s3_force_destroy" {
    description = "Force destroy S3 bucket even if it contains objects"
    type        = bool
}

variable "server_cpu" {
    description = "MLflow server CPU"
    type        = number
}

variable "server_memory" {
    description = "MLflow server memory"
    type        = number
}

variable "server_autoscaling_max_capacity" {
    description = "MLflow server autoscaling max capacity"
    type        = number
}

variable "server_port" {
    description = "MLflow server port"
    type        = number
}

variable "server_name" {
    description = "MLflow server name"
    type        = string
}


variable "env_name" {
    description = "Environment name"
    type        = string
}

variable "project" {
    description = "Project name"
    type        = string
}