

module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc?ref=12caf80"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr_block

  azs              = slice(data.aws_availability_zones.this.names, 0, min(3, length(var.vpc_private_subnets)))
  private_subnets  = var.vpc_private_subnets
  public_subnets   = var.vpc_public_subnets
  database_subnets = var.vpc_db_subnets

  enable_vpn_gateway = true
  map_public_ip_on_launch = false

  enable_nat_gateway      = true
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false

  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = true

}

module "s3_bucket" {
  source = "git::github.com/terraform-aws-modules/terraform-aws-s3-bucket?ref=d8ad14f"

  bucket = "${var.project}-${var.env_name}-mlflow-artifact-store"
  acl    = "private"

  force_destroy = var.s3_force_destroy
  control_object_ownership = true
  object_ownership         = "ObjectWriter"

  versioning = {
    enabled = false
  }

}

module "ecr" {
  source = "git::github.com/terraform-aws-modules/terraform-aws-ecr?ref=841b3c7"

  repository_name = "mlflow-server"
  repository_image_tag_mutability = "IMMUTABLE"
  repository_force_delete = true

  repository_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 2 images",
        selection = {
          tagStatus     = "tagged",
          tagPrefixList = ["v"],
          countType     = "imageCountMoreThan",
          countNumber   = 2
        },
        action = {
          type = "expire"
        }
      }
    ]
  })

}


resource "null_resource" "build_and_push_server_image" {
  provisioner "local-exec" {
    command = <<-EOT
    aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin ${module.ecr.repository_url}
    docker build \
      --platform=linux/amd64 \
      -t ${module.ecr.repository_url}:${local.dockerfile_sha} \
      "${path.module}/docker"
    docker push ${module.ecr.repository_url}:${local.dockerfile_sha}
    EOT
  }

  triggers = {
    dockerfile_sha = local.dockerfile_sha
  }
}


module "vpn" {
  #checkov:skip=CKV_TF_1: "Terraform AWS VPN Client module"
  source  = "babicamir/vpn-client/aws"
  version = "1.0.1"
  organization_name      = "default"
  project-name           = var.project
  environment            = var.env_name
  # Network information
  vpc_id                 = module.vpc.vpc_id
  subnet_id              = module.vpc.public_subnets[0]
  client_cidr_block      = var.vpn_cidr_block # It must be different from the primary VPC CIDR
  # VPN config options
  split_tunnel           = "true" # or false
  vpn_inactive_period = "300" # seconds
  session_timeout_hours  = "8"
  logs_retention_in_days = "7"
  # List of users to be created
  aws-vpn-client-list    = var.vpn_clients
}

module "db_sg" {
  source = "git::github.com/terraform-aws-modules/terraform-aws-security-group?ref=eb9fb97"

  name        = "db"
  description = "Allows traffic from private subnets"
  vpc_id      = module.vpc.vpc_id

  # ingress_cidr_blocks      = module.vpc.private_subnets_cidr_blocks
  # ingress_rules            = ["mysql-3306-tcp"]
  ingress_with_cidr_blocks = [for subnet_cidr_block in module.vpc.private_subnets_cidr_blocks : 
    {
      from_port   = tonumber(var.db_port)
      to_port     = tonumber(var.db_port)
      protocol    = "TCP"
      description = "DB access from private subnets"
      cidr_blocks = subnet_cidr_block
    }
  ]
}


module "db" {
  source = "git::github.com/terraform-aws-modules/terraform-aws-rds?ref=4481ddd"
  identifier = "mlflow-data-store"

  db_name = var.db_name

  engine            = "mysql"
  engine_version    = "8.0"
  major_engine_version = "8.0"
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  family = "mysql8.0"

  username = var.db_username
  port     = var.db_port
  manage_master_user_password = true

  # DB subnet group
  db_subnet_group_name       = "mlflow-db-subnet-group"
  create_db_subnet_group     =  true
  subnet_ids                 =  module.vpc.database_subnets
  vpc_security_group_ids     = [module.db_sg.security_group_id]

  option_group_name = "mlflow-server-option-group"
  skip_final_snapshot = true

  # Database Deletion Protection
  deletion_protection = var.db_deletion_protection

}


data "aws_secretsmanager_secret_version" "master_user_password" {
  secret_id = module.db.db_instance_master_user_secret_arn
}

locals {
  db_password = jsondecode(data.aws_secretsmanager_secret_version.master_user_password.secret_string)["password"]
}

module "alb" {
  source = "git::github.com/terraform-aws-modules/terraform-aws-alb?ref=5121d71"

  name    = "mlflow-server-lb"
  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets
  load_balancer_type = "application"
  internal = true
  enable_deletion_protection = false
  # security_groups = [module.alb_sg.security_group_id]
  # Security Group
  security_group_ingress_rules = {
    http_vpc = {
      from_port   = var.server_port
      to_port     = var.server_port
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
    http_vpn = {
      from_port   = var.server_port
      to_port     = var.server_port
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = var.vpn_cidr_block
    }
  }
  security_group_egress_rules = {
    vpc_all = {
      ip_protocol = "-1"
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }

  listeners = {
    mlflow-server-http-forward = {
      port     = var.server_port
      protocol = "HTTP"
      forward = {
        target_group_key = "mlflow_server_tgt_group"
      }
    }
  }

  target_groups = {
    mlflow_server_tgt_group = {
      backend_protocol = "HTTP"
      backend_port     = var.server_port
      target_type      = "ip"
      load_balancing_cross_zone_enabled = true

      create_attachment = false
    }
  }

}


module "ecs_cluster" {
  source = "git::github.com/terraform-aws-modules/terraform-aws-ecs.git//modules/cluster?ref=3b70e1e" 

  cluster_name = "${var.project}-ecs-cluster"
  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 100
      }
    }
  }
}

module "ecs_service" {
  source = "git::github.com/terraform-aws-modules/terraform-aws-ecs.git//modules/service?ref=3b70e1e"
  
  cluster_arn = module.ecs_cluster.arn
  name = "${var.project}-mlflow-service"
  depends_on = [null_resource.build_and_push_server_image, module.alb, module.db]

  cpu    = var.server_cpu
  memory = var.server_memory

  autoscaling_min_capacity = 1
  autoscaling_max_capacity = var.server_autoscaling_max_capacity

  subnet_ids = module.vpc.private_subnets

  enable_execute_command = true

  container_definitions = {

    (var.server_name) = {
      cpu    = var.server_cpu
      memory = var.server_memory

      readonly_root_filesystem = false

      image = "${module.ecr.repository_url}:${local.dockerfile_sha}"
      environment = [
        {
          name  = "BUCKET"
          value = "s3://${var.project}-${var.env_name}-mlflow-artifact-store"
        },
        {
          name  = "USERNAME"
          value = var.db_username
        },
        {
          name  = "PASSWORD"
          value = local.db_password
        },
        {
          name  = "DB_ENDPOINT" # host:port
          value = module.db.db_instance_endpoint
        }, 
        {
          name  = "DATABASE"
          value = var.db_name
        },
        {
          name = "MLFLOW_PORT",
          value = "${var.server_port}"
        }
      ]
      essential = true
      log_configuration = {
        logDriver = "awslogs"
        options = {
          awslogs-create-group  = "true"
          awslogs-group         = "/ecs/${var.project}/mlflow-server"
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "container"
        }
      }
      port_mappings = [
        {
          containerPort = var.server_port
          hostPort      = var.server_port
          name          = var.server_name
          protocol      = "tcp"
        },
      ]
    }
  }

  load_balancer = {
    service = {
      target_group_arn = module.alb.target_groups["mlflow_server_tgt_group"].arn
      container_name   = var.server_name
      container_port   = var.server_port
    }
  }

  create_security_group = true
  security_group_rules = {
    alb_ingress = {
      type                     = "ingress"
      from_port                = var.server_port
      to_port                  = var.server_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = module.alb.security_group_id
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  create_iam_role = true
  tasks_iam_role_name        = "${var.server_name}-task-role"
  tasks_iam_role_description = "Role for MLFlow server task"
  tasks_iam_role_statements = [
    {
      sid = "AllowLogs",
      effect = "Allow",
      actions = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:CreateLogGroup"
      ],
      resources = ["*"]
    },
    {
      sid = "AllowS3IO",
      effect = "Allow",
      actions = [
        "s3:GetObject",
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:HeadObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      resources = [module.s3_bucket.s3_bucket_arn, "${module.s3_bucket.s3_bucket_arn}/*"]
    },
  ]



  create_task_exec_policy   = true
  create_task_exec_iam_role = true
  task_exec_iam_role_name   = "${var.server_name}-task-exec-role"
  task_exec_iam_role_description = "Role for MLFlow server task execution"
  task_exec_iam_statements = [
    {
      sid = "PullContainerImage",
      effect = "Allow",
      actions = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
      ],
      resources = [module.ecr.repository_arn]
    },
    {
      sid = "AllowS3BucketAccess",
      effect = "Allow",
      actions = [
        "s3:GetObject",
        "s3:GetBucketLocation",
        "s3:ListBucket",
        "s3:HeadObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      resources = ["*"]
    },
    {
      sid = "AllowLogs",
      effect = "Allow",
      actions = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:CreateLogGroup"
      ],
      resources = ["*"]
    }
  ]

}