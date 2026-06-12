# URL de los repositorios ECR
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

# IP privada de MySQL (la que usan los microservicios en ECS)
output "mysql_private_ip" {
  description = "IP privada de la EC2 de MySQL (usada en SPRING_DATASOURCE_URL)"
  value       = aws_instance.mysql.private_ip
}

output "eks_cluster_name" {
  description = "Nombre del cluster EKS"
  value       = aws_eks_cluster.main.name
}

output "eks_kubeconfig_command" {
  description = "Comando para configurar kubectl localmente"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "alb_dns_name" {
  description = "URL pública del proyecto"
  value       = aws_lb.main.dns_name
}
