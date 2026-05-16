terraform {
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

############################
# VPC
############################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-public"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rt-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

############################
# SECURITY GROUPS
############################

# SG principal: frontend (80) + microservicios (8081, 8082)
resource "aws_security_group" "app" {
  name   = "${var.project_name}-sg-app"
  vpc_id = aws_vpc.main.id

  # Frontend accesible desde internet
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # ms-ventas — solo desde dentro de la VPC
  ingress {
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # ms-despachos — solo desde dentro de la VPC
  ingress {
    from_port   = 8082
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-app"
  }
}

# SG para la EC2 de MySQL — solo acepta 3306 desde el SG de la app
resource "aws_security_group" "mysql" {
  name   = "${var.project_name}-sg-mysql"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # SSH para administración ( puede removerse en producción)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg-mysql"
  }
}

############################
# ECR — 3 repositorios
############################

resource "aws_ecr_repository" "ms_ventas" {
  name         = "${var.project_name}-ms-ventas"
  force_delete = true
}

resource "aws_ecr_repository" "ms_despachos" {
  name         = "${var.project_name}-ms-despachos"
  force_delete = true
}

resource "aws_ecr_repository" "frontend" {
  name         = "${var.project_name}-frontend"
  force_delete = true
}

############################
# EC2 — MySQL
# MySQL corre en contenedor Docker sobre una EC2
############################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "mysql" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.mysql.id]
  key_name               = var.key_pair_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash

    yum update -y
    yum install -y docker

    systemctl start docker
    systemctl enable docker

    # Esperar a que Docker esté listo
    until docker info > /dev/null 2>&1; do
      echo "Esperando Docker..."
      sleep 3
    done

    # Levantar MySQL con volumen para persistencia
    docker run -d \
      --name mysql \
      --restart unless-stopped \
      -e MYSQL_ROOT_PASSWORD=${var.db_password} \
      -e MYSQL_DATABASE=${var.db_name} \
      -e MYSQL_ROOT_HOST=% \
      -v mysql_data:/var/lib/mysql \
      -p 3306:3306 \
      --log-opt max-size=10m \
      --log-opt max-file=3 \
      mysql:8 \
      --bind-address=0.0.0.0 \
      --performance-schema=OFF
  EOF

  tags = {
    Name = "${var.project_name}-mysql"
  }
}

############################
# CLOUDWATCH LOGS
############################

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
}

resource "null_resource" "wait_for_mysql" {
  depends_on = [aws_instance.mysql]

  provisioner "local-exec" {
    command = "sleep 180"
  }
}

############################
# ECS CLUSTER
############################

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# AWS Academy provee el rol LabRole con los permisos necesarios
data "aws_iam_role" "lab" {
  name = "LabRole"
}

############################
# TASK DEFINITION
# Un task con los 3 contenedores juntos:
# frontend + ms-ventas + ms-despachos
############################

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = data.aws_iam_role.lab.arn

  container_definitions = jsonencode([

    # ── ms-ventas ──────────────────────────────
    {
      name  = "ms-ventas"
      image = "${aws_ecr_repository.ms_ventas.repository_url}:latest"

      portMappings = [
        { containerPort = 8081 }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:8081/api/v1/ventas || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 5
        startPeriod = 120
      }

      environment = [
        {
          name  = "DB_ENDPOINT"
          value = aws_instance.mysql.private_ip
        },
        {
          name  = "DB_PORT"
          value = "3306"
        },
        {
          name  = "DB_NAME"
          value = var.db_name
        },
        {
          name  = "DB_USERNAME"
          value = "root"
        },
        {
          name  = "DB_PASSWORD"
          value = var.db_password
        },
        {
          name  = "SPRING_JPA_HIBERNATE_DDL_AUTO"
          value = "update"
        },
        {
          name  = "SPRING_PROFILES_ACTIVE"
          value = "prod"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ms-ventas"
        }
      }
    },

    # ── ms-despachos ───────────────────────────
    {
      name  = "ms-despachos"
      image = "${aws_ecr_repository.ms_despachos.repository_url}:latest"

      portMappings = [
        { containerPort = 8082 }
      ]

      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:8082/api/v1/despachos || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 5
        startPeriod = 120
      }

      environment = [
        {
          name  = "DB_ENDPOINT"
          value = aws_instance.mysql.private_ip
        },
        {
          name  = "DB_PORT"
          value = "3306"
        },
        {
          name  = "DB_NAME"
          value = var.db_name
        },
        {
          name  = "DB_USERNAME"
          value = "root"
        },
        {
          name  = "DB_PASSWORD"
          value = var.db_password
        },
        {
          name  = "SPRING_JPA_HIBERNATE_DDL_AUTO"
          value = "update"
        },
        {
          name  = "SPRING_PROFILES_ACTIVE"
          value = "prod"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ms-despachos"
        }
      }
    },

    # ── frontend ───────────────────────────────
    {
      name  = "frontend"
      image = "${aws_ecr_repository.frontend.repository_url}:latest"

      portMappings = [
        { containerPort = 8080 }
      ]
       healthCheck = {
          command     = ["CMD-SHELL", "wget -qO- http://localhost:8080 || exit 1"]
          interval    = 30
          timeout     = 5
          retries     = 3
          startPeriod = 30
        }


      dependsOn = [
        { containerName = "ms-ventas",    condition = "START" },
        { containerName = "ms-despachos", condition = "START" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "frontend"
        }
      }
    }

  ])
}

############################
# ECS SERVICE
############################

resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"
  desired_count   = 1
  depends_on = [null_resource.wait_for_mysql]

  force_new_deployment = true

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets          = [aws_subnet.public.id]
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }
}
