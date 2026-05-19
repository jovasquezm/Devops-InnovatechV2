
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

#Requisitos Previos
Antes de comenzar, asegúrate de contar con las siguientes herramientas instaladas y configuradas:

*Terraform CLI (Versión >= 1.0)

*AWS CLI configurado con tus credenciales

*Docker & Docker Compose

*Una cuenta activa de AWS Academy (o cuenta AWS con permisos suficientes)

Flujo de Uso (Terraform)
⚠️ Nota: Este flujo solo se ejecuta una vez al inicio para montar la infraestructura, no en cada presentación. Crea todo en AWS.

Bash
# Cambiar al directorio de infraestructura
cd infra/

# Inicializar y descargar los plugins de AWS (solo la primera vez)
terraform init

# Mostrar qué recursos se van a crear, sin aplicar cambios aún
terraform plan

# Crear la infraestructura real en AWS
terraform apply

Al terminar el apply, Terraform imprimirá las variables de salida. Puedes consultarlas en cualquier momento con:

Bash
# Mostrar las URLs de ECR, IPs y nombres de cluster
terraform output

-----------Autenticación de Docker en AWS ECR---------
Para realizar la subida de las imágenes de los contenedores a los repositorios privados de AWS (ECR), se debe autenticar el cliente local de Docker utilizando el ID de la cuenta de AWS obtenido en los outputs del paso anterior:

Bash
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
  <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

------------Pruebas Locales (Docker Compose)--------------
Antes de realizar el despliegue en la nube, se recomienda validar el correcto funcionamiento de los contenedores en el entorno local (Frontend, Microservicios y Base de Datos).

Bash
# Regresar a la raíz del proyecto
cd ..

# Configurar el archivo de variables de entorno locales
cp .env.example .env
# (Proceder a editar el archivo .env con los valores correspondientes)

# Levantar el entorno local construyendo las imágenes de los contenedores
docker compose up --build

*Verificar el estado de los servicios: docker compose ps

*Interactuar con la aplicación: Abrir el navegador en http://localhost

*Detener el entorno (preservando datos de la BD): docker compose down

------------------Despliegue Automatizado en AWS (GitHub Actions) -------------------

El pipeline de Despliegue Continuo (CD) hacia Amazon ECS se activa de forma automatizada al realizar un push a la rama dedicada de deployment (deploy).

Bash
# Consolidar los cambios en la rama principal e integrarlos a la rama de despliegue
git checkout main
git pull
git checkout deploy
git merge main
git push origin deploy


----------------Verificación en Producción (AWS)----------------------
Para comprobar que los servicios se han desplegado correctamente en la nube y están corriendo:

Bash
# Verificar que las tareas de ECS se encuentren estables y en ejecución
aws ecs describe-services \
  --cluster innovatech-cluster \
  --services innovatech-service \
  --query "services[0].runningCount"




