variable "aws_region" {
  description = "Región AWS donde se despliega la infraestructura"
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en todos los recursos"
  default     = "innovatech"
}

variable "db_password" {
  description = "Contraseña root de MySQL"
  sensitive   = true
}

variable "db_name" {
  description = "Nombre de la base de datos"
  default     = "innovatech_db"
}

variable "key_pair_name" {
  description = "Nombre del Key Pair en AWS para acceso SSH a la EC2 de MySQL"
}
