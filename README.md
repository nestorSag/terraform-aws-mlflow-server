# terraform-aws-mlflow-server

This module provisions an MLFlow server on AWS using RDS and S3 as storage backends. The server runs as an autoscaling container in an ECS task.

---

## Details

A dedicated VPC is created for the server, which is behind a private load balancer. It can be accessed through the VPN created as part of the module. Control groups and policies are used to grant minimal sets of permissions to each service. 


## Reaching the server

Once provisioned:

1. The `vpn_bucket` module output points to the S3 bucket storing `.ovpn` files. Download yours.

2. Load your `.ovpn` file into the [AWS VPN client](https://aws.amazon.com/vpn/client-vpn-download/)

3. Log into the VPN

4. The server endpoint is in the `mlflow_endpoint` module output. You should be able to open it in a browser.

## NOTES

* The module builds and uploads the server's Docker image, so `docker` needs to be installed and running.

* At this time only MySQL is supported in the metadata backend.

* The delete protection features for RDS and S3 are disabled by default. Enable them if needed.

* The server runs on Python 3.12, and installs the latest MLFlow version available.


## Architecture

![Architecture diagram](other/static/mlflow-server.png)

## Usage

See an example below with all input parameters

```hcl
module "mlflow_server" {
    source  = "nestorSag/mlflow-server/aws"
    version = "1.0.0"

    region   = "us-east-1"
    env_name = "prod"
    project  = "mlops-platform"

    vpc_cidr_block         = "10.0.0.0/16"
    vpc_private_subnets    = ["10.0.0.0/27", "10.0.0.32/27"]
    vpc_public_subnets     = ["10.0.0.64/27", "10.0.0.96/27"]
    vpc_db_subnets         = ["10.0.0.128/27", "10.0.0.160/27"]

    vpn_cidr_block = "10.1.0.0/16"
    vpn_clients    = ["root", "dev1", "dev2"] #Do not delete "root" user!

    db_engine              = "mysql"
    db_engine_version      = "8.0"
    db_family              = "mysql8.0"
    db_instance_class      = "db.t3.micro"
    db_allocated_storage   = 10
    db_name                = "mlflowdb"
    db_username            = "mlflow_db_user"
    db_port                = "3306"
    db_deletion_protection = false

    server_cpu                      = 1024
    server_memory                   = 4096
    server_autoscaling_max_capacity = 2
    server_port                     = 5000
    server_name                     = "mlflow_server"

    s3_force_destroy = true
}
```
