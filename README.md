# Innovatech Chile - DevOps Infrastructure with Terraform & AWS

Este repositorio contiene el diseño, gestión y despliegue automatizado de la infraestructura en la nube para 
**Innovatech Chile**. El proyecto implementa una arquitectura de microservicios 
contenedorizados mediante un enfoque moderno de Infraestructura como Código (IoC) y Continuous Deployment (CD).

####Estructura del Proyecto#####

```text
Devops-InnovatechV2/
├── infra/                  # Código de Terraform para la infraestructura AWS
│   ├── main.tf             # Definición de recursos (VPC, ECS, ECR, etc.)
│   ├── providers.tf        # Configuración del proveedor de AWS
│   ├── variables.tf        # Definición de variables globales
│   └── outputs.tf          # Salidas del despliegue (URLs, IPs, IDs)
├── .github/workflows/      # Automatización CI/CD
│   └── cd.yml              # Pipeline de GitHub Actions para el despliegue en ECS
├── docker-compose.yml      # Configuración para pruebas en ambiente local
└── README.md               # Documentación del proyecto





