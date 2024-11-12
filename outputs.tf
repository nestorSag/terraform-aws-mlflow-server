output "mlflow_tracking_uri" {
  description = "URL of load balancer"
  value       = "http://${module.alb.dns_name}:${var.server_port}"
}

output "mlflow_artifact_bucket" {
  description = "S3 bucket for MLflow artifacts"
  value       = "${var.project}-${var.env_name}-mlflow-artifact-store"
}

output "vpn_bucket" {
  description = "S3 bucket that keeps .ovpn files for VPN clients"
  value       = "${var.project}-{var.env_name}-vpn-config-files"
}

output vpc_id {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}