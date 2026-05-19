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




----Requisitos Previos------
Antes de comenzar, asegúrate de contar con las siguientes herramientas instaladas y configuradas:

Terraform CLI (Versión >= 1.0)

AWS CLI configurado

Docker & Docker Compose

Una cuenta activa de AWS Academy (o cuenta AWS con permisos suficientes)


 -------Flujo de uso---------------
Solo se ejecuta una vez al inicio, no en cada presentación. Crea todo en AWS:
bashcd infra/

terraform init        # descarga los plugins de AWS (solo la primera vez)
terraform plan        # muestra qué va a crear, sin crear nada aún
terraform apply       # crea la infraestructura real en AWS
Al terminar el apply, Terraform imprime los outputs:
bashterraform output      # muestra las URLs de ECR, IPs, nombres de cluster




---------------Autenticación de Docker en AWS ECR---------
Para realizar la subida de las imágenes de los contenedores a los repositorios privados de AWS (ECR),
se debe autenticar el cliente local de Docker utilizando el ID de la cuenta de AWS obtenido en los outputs del paso anterior:

aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
  <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

------------ Pruebas Locales (Docker Compose)-----------------
Antes de realizar el despliegue en la nube, se recomienda validar el correcto funcionamiento
de los contenedores en el entorno local (Frontend, Microservicios y Base de Datos).

cd ..   # Regresar a la raíz del proyecto

# Configurar el archivo de variables de entorno locales
cp .env.example .env
# (Proceder a editar el archivo .env con los valores correspondientes)

# Levantar el entorno local construyendo las imágenes de los contenedores
docker compose up --build

Para verificar el estado de los servicios: docker compose ps

Para interactuar con la aplicación, abrir el navegador en: http://localhost

Para detener el entorno preservando los datos de la base de datos: docker compose down


-------------------Despliegue Automatizado en AWS (GitHub Actions) ---------------------
El pipeline de Despliegue Continuo (CD) hacia Amazon ECS se activa de forma
automatizada al realizar un push a la rama dedicada de deployment (deploy).

# Consolidar los cambios en la rama principal e integrarlos a la rama de despliegue
git checkout main
git pull
git checkout deploy
git merge main
git push origin deploy

----------------Verificación en Producción (AWS)----------------------
# Verificar que las tareas de ECS se encuentren estables y en ejecución
aws ecs describe-services \
  --cluster innovatech-cluster \
  --services innovatech-service \
  --query "services[0].runningCount"


