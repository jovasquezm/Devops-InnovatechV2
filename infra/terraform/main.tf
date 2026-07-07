terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

############################
# 1. VPC Y RED (Multi-AZ para el ALB)
############################
data "aws_availability_zones" "available" {}

resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "${var.project_name}-vpc" }
}

# 2 Subredes Públicas (Para el ALB y NAT Gateway)
resource "aws_subnet" "eks_subnet_public" {
  count                   = 2
  vpc_id                  = aws_vpc.eks_vpc.id
  
  # La primera pasada toma la .10.0, la segunda toma la .11.0
  cidr_block              = ["10.0.10.0/24", "10.0.11.0/24"][count.index]
  
  # La primera pasada va a la zona 'a', la segunda va a la zona 'b'
  availability_zone       = ["us-east-1a", "us-east-1b"][count.index]
  
  map_public_ip_on_launch = true
  
  tags = { Name = "eks-subnet-public-${count.index + 1}" }
}

# 2 Subredes Privadas (Para Backends, Frontend y MySQL)
resource "aws_subnet" "eks_subnet_private" {
  count             = 2
  vpc_id            = aws_vpc.eks_vpc.id
  
  # Aquí aplicamos tus rangos solicitados
  cidr_block        = ["10.0.20.0/24", "10.0.30.0/24"][count.index]
  
  # Misma lógica de replicación en zonas distintas
  availability_zone = ["us-east-1a", "us-east-1b"][count.index]
  
  tags = { Name = "eks-subnet-private-${count.index + 1}" }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.eks_vpc.id
}

# NAT Gateway (Obligatorio para que las subredes privadas tengan salida a internet)
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.eks_subnet_public[0].id
  depends_on    = [aws_internet_gateway.main]
}

# Tablas de Ruteo
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.eks_subnet_public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.eks_subnet_private[count.index].id
  route_table_id = aws_route_table.private.id
}

############################
# 2. SECURITY GROUPS
############################

# SG del Balanceador (Accesible desde internet)
resource "aws_security_group" "alb_sg" {
  name   = "${var.project_name}-alb-sg"
  vpc_id = aws_vpc.eks_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG de los Contenedores ECS (Solo accesibles desde el ALB)
resource "aws_security_group" "ecs_sg" {
  name   = "${var.project_name}-ecs-sg"
  vpc_id = aws_vpc.eks_vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8082
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG de MySQL (Accesible desde los contenedores y permite SSH dentro de la VPC por si acaso)
resource "aws_security_group" "mysql_sg" {
  name   = "${var.project_name}-mysql-sg"
  vpc_id = aws_vpc.eks_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.eks_vpc.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

############################
# 3. ECR Y LOGS
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

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
}

############################
# 4. EC2 — MySQL (En subred privada)
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
  subnet_id              = aws_subnet.eks_subnet_private[0].id
  vpc_security_group_ids = [aws_security_group.mysql_sg.id]
  key_name               = var.key_pair_name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y docker
    systemctl start docker
    systemctl enable docker
    until docker info > /dev/null 2>&1; do
      echo "Esperando Docker..."
      sleep 3
    done
    docker run -d --name mysql --restart unless-stopped -e MYSQL_ROOT_PASSWORD=${var.db_password} -e MYSQL_DATABASE=${var.db_name} -e MYSQL_ROOT_HOST=% -v mysql_data:/var/lib/mysql -p 3306:3306 --log-opt max-size=10m --log-opt max-file=3 mysql:8-oracle --bind-address=0.0.0.0 --performance-schema=OFF
  EOF
  tags = { Name = "${var.project_name}-mysql" }
}


############################
# 5. APPLICATION LOAD BALANCER (ALB)
############################
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.eks_subnet_public[*].id
}

resource "aws_lb_target_group" "frontend" {
  name        = "tg-frontend"
  port        = 30080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.eks_vpc.id
  target_type = "instance"
  health_check {
     path = "/"
     port = "30080"
  }
}

resource "aws_lb_target_group" "ventas" {
  name        = "tg-ventas"
  port        = 30081
  protocol    = "HTTP"
  vpc_id      = aws_vpc.eks_vpc.id
  target_type = "instance"
  health_check {
     path = "/actuator/health"
     port = "30081"
  }
}

resource "aws_lb_target_group" "despachos" {
  name        = "tg-despachos"
  port        = 30082
  protocol    = "HTTP"
  vpc_id      = aws_vpc.eks_vpc.id
  target_type = "instance"
  health_check {
     path = "/actuator/health"
     port = "30082"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "api_ventas" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ventas.arn
  }
  condition { 
    path_pattern {
       values = ["/api/ventas/*"]
    }
  }
}

resource "aws_lb_listener_rule" "api_despachos" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.despachos.arn
  }
  condition { 
    path_pattern {
       values = ["/api/despachos/*"]
    }
  }
}

############################
# 6. EKS CLUSTER E IAM (Usando LabRole para AWS Academy)
############################
data "aws_iam_role" "lab" {
  name = "LabRole"
}

resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-eks-cluster"
  role_arn = data.aws_iam_role.lab.arn

  vpc_config {
    subnet_ids = concat(aws_subnet.eks_subnet_public[*].id, aws_subnet.eks_subnet_private[*].id)
  }
}

############################
# 7. EKS NODE GROUP (Los servidores reales)
############################
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-nodes"
  node_role_arn   = data.aws_iam_role.lab.arn
  subnet_ids      = aws_subnet.eks_subnet_private[*].id
  
  # Usamos t3.medium porque t3.micro se queda sin RAM para los demonios de K8s
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  depends_on = [aws_eks_cluster.main]
}

############################
# 8. INTEGRACIÓN EKS <-> ALB <-> MYSQL
############################

# 8.1 Permitir que el ALB envíe tráfico a los NodePorts de EKS (30080 - 30082)
resource "aws_security_group_rule" "alb_to_eks_nodes" {
  type                     = "ingress"
  from_port                = 30080
  to_port                  = 30082
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.alb_sg.id
}

# 8.2 Permitir que los Nodos EKS se conecten a la EC2 de MySQL (Puerto 3306)
resource "aws_security_group_rule" "eks_nodes_to_mysql" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  security_group_id        = aws_security_group.mysql_sg.id
  source_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

# 8.3 Conectar dinámicamente los Nodos EKS a los Target Groups del ALB
# Terraform extraerá el Auto Scaling Group que EKS crea por detrás y lo pegará al ALB
resource "aws_autoscaling_attachment" "asg_frontend" {
  autoscaling_group_name = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.frontend.arn
}

resource "aws_autoscaling_attachment" "asg_ventas" {
  autoscaling_group_name = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.ventas.arn
}

resource "aws_autoscaling_attachment" "asg_despachos" {
  autoscaling_group_name = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.despachos.arn
}

