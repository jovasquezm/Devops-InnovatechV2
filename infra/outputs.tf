# URL de los repositorios ECR
# Estos valores se usan en el cd.yml como ECR_REGISTRY
output "ecr_ms_ventas" {
  description = "URL del repositorio ECR de ms-ventas"
  value       = aws_ecr_repository.ms_ventas.repository_url
}

output "ecr_ms_despachos" {
  description = "URL del repositorio ECR de ms-despachos"
  value       = aws_ecr_repository.ms_despachos.repository_url
}

output "ecr_frontend" {
  description = "URL del repositorio ECR del frontend"
  value       = aws_ecr_repository.frontend.repository_url
}

# IP pública de la EC2 de MySQL para verificar conexión
output "mysql_public_ip" {
  description = "IP pública de la EC2 donde corre MySQL"
  value       = aws_instance.mysql.public_ip
}

# IP privada de MySQL (la que usan los microservicios en ECS)
output "mysql_private_ip" {
  description = "IP privada de la EC2 de MySQL (usada en SPRING_DATASOURCE_URL)"
  value       = aws_instance.mysql.private_ip
}

# Nombre del cluster ECS necesario en el cd.yml
output "ecs_cluster_name" {
  description = "Nombre del cluster ECS"
  value       = aws_ecs_cluster.main.name
}

# Nombre del servicio ECS necesario en cd.yml
output "ecs_service_name" {
  description = "Nombre del servicio ECS"
  value       = aws_ecs_service.app.name
}
