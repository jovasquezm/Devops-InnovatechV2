# Innovatech Chile - DevOps Infrastructure con Terraform & AWS

Este repositorio contiene el diseño, gestión y despliegue automatizado de la infraestructura en la nube para *Innovatech Chile*. El proyecto implementa una arquitectura de microservicios contenedorizados mediante un enfoque moderno de Infraestructura como Código (IaC) e Integración continua/Despliegue continuo (CD).

### 🧭 Estructura del Proyecto

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
```

### 🐳 1. Contenedorización (Frontend y Backend)

Para que las aplicaciones corran rápido y de forma segura, armamos los Dockerfiles pensando en un entorno de producción real y aplicamos las siguientes prácticas:

* **Multi-Stage Builds:** Dividimos el Dockerfile en dos pasos. Primero instalamos todo lo necesario para compilar el código. Después, tomamos solo el resultado final y lo pasamos a una imagen base súper liviana. Esto nos ayuda a que la imagen pese mucho menos, sea más rápida de desplegar y de pasada eliminamos herramientas de desarrollo que podrían ser un riesgo de seguridad.
* **Usuario No Root:** Por defecto, Docker corre los contenedores como administrador (root). Nosotros configuramos un usuario con permisos limitados en el sistema (por ejemplo, el usuario node). Así, si alguien logra vulnerar la app desde afuera, se queda atrapado sin permisos para hacerle daño a la infraestructura.
* **Limpieza y Optimización de Capas:** Ordenamos los comandos RUN y limpiamos la caché de instalación en el mismo paso para no generar basura. También dejamos la copia del código fuente al final para aprovechar la caché de Docker y que los builds sean mucho más rápidos.

### 📦 2. Orquestación con Docker Compose

Usamos el archivo `docker-compose.yml` para levantar todo el ecosistema de una sola vez, tanto para probar en local como en los servidores.

Acá declaramos de forma aislada los servicios de frontend, backend y la base de datos. Para que nada se caiga al iniciar, le pusimos un `depends_on` al backend; de esta forma, espera a que la base de datos esté 100% lista y recibiendo conexiones antes de arrancar. También creamos redes internas separadas. El frontend no tiene forma de hablar directo por red con la base de datos, lo que suma una capa extra de seguridad.

### 💾 3. Persistencia de Datos

Para no perder la información de Innovatech si se reinicia o se actualiza un contenedor, configuramos almacenamiento persistente.

Para la base de datos en producción elegimos usar **Named Volumes**. Estos volúmenes los maneja Docker directamente, son más rápidos en los servidores Linux de AWS, garantizan que los archivos estén aislados de forma segura y nos evitan dolores de cabeza con los permisos de carpetas.

Por otro lado, para cuando estamos programando y desarrollando en local, usamos **Bind Mounts**. Esto nos permite conectar la carpeta de nuestro código directo al contenedor, así podemos ver los cambios que hacemos en vivo (Hot Reload) sin tener que compilar la imagen a cada rato.

### 🔄 4. Automatización y CI/CD con GitHub Actions

Para no hacer los despliegues a mano y evitar errores, armamos un pipeline automatizado en el archivo `.github/workflows/cd.yml`.

El flujo es súper directo: cada vez que hacemos un push a la rama deploy, GitHub Actions levanta un entorno virtual, compila las nuevas imágenes Docker, se autentica y luego hace el despliegue automático.

Obviamente, para no dejar nuestras llaves y contraseñas a la vista en el repositorio público, guardamos todas las credenciales de AWS dentro de los GitHub Secrets.

### 🌐 5. Seguridad de Redes en AWS EC2

Configuramos los Security Groups en AWS para que nadie pueda entrar por donde no debe, aislando las distintas partes del proyecto:

* **Frontend (Acceso Público):** Es el único recurso expuesto a internet. Le abrimos los puertos 80 y 443 para que los usuarios puedan entrar a la página web desde cualquier lado.
* **Backend (Acceso Protegido):** Lo bloqueamos por completo. Su Security Group rechaza todo el tráfico directo que venga desde internet. Solo acepta conexiones en el puerto de su API si vienen específicamente del Security Group del Frontend. De esta forma, protegemos los endpoints y la base de datos de ataques externos.

### ⚙️ 6. Guía de Uso y Comandos

#### Requisitos Previos 
Antes de comenzar, asegúrate de contar con las siguientes herramientas instaladas y configuradas:
* Terraform CLI (Versión >= 1.0)
* AWS CLI configurado con tus credenciales
* Docker & Docker Compose
* Una cuenta activa de AWS Academy 

#### Flujo de Uso (Terraform)
Este flujo se ejecuta una vez al inicio para montar la infraestructura. Crea todo en AWS.

```bash
# Cambiar al directorio de infraestructura
cd infra/

# Inicializar y descargar los plugins de AWS (solo la primera vez)
terraform init

# Ingresar las credenciales de AWS academy
aws configure

# Mostrar qué recursos se van a crear, sin aplicar cambios aún
terraform plan

# Crear la infraestructura real en AWS
terraform apply

# Al terminar el apply, Terraform imprimirá las variables de salida.
# Puedes consultarlas en cualquier momento con:
terraform outputs

# Mostrar las URLs de ECR, IPs y nombres de cluster
terraform output
```

#### Autenticación de Docker en AWS ECR
Para realizar la subida de las imágenes de los contenedores a los repositorios privados de AWS (ECR), se debe autenticar el cliente local de Docker utilizando el ID de la cuenta de AWS obtenido en los outputs del paso anterior:

```bash
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
  <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```

#### Pruebas Locales (Docker Compose)
Antes de realizar el despliegue en la nube, se recomienda validar el correcto funcionamiento de los contenedores en el entorno local (Frontend, Microservicios y Base de Datos).

```bash
# Regresar a la raíz del proyecto
cd ..

# Configurar el archivo de variables de entorno locales
cp .env.example .env
# (Proceder a editar el archivo .env con los valores correspondientes)

# Levantar el entorno local construyendo las imágenes de los contenedores
docker compose up --build

# Verificar el estado de los servicios: 
docker compose ps

# Interactuar con la aplicación: Abrir el navegador en http://localhost

# Detener el entorno (preservando datos de la BD):
docker compose down
```

#### Despliegue Automatizado en AWS (GitHub Actions)
El pipeline de Despliegue Continuo (CD) hacia Amazon ECS se activa de forma automatizada al realizar un push a la rama dedicada de deployment (deploy).

```bash
# Consolidar los cambios en la rama principal e integrarlos a la rama de despliegue
git checkout main
git pull
git checkout deploy
git merge main
git push origin deploy
```

#### Verificación en Producción (AWS)
Para comprobar que los servicios se han desplegado correctamente en la nube y están corriendo:

```bash
# Verificar que las tareas de ECS se encuentren estables y en ejecución
aws ecs describe-services \
  --cluster innovatech-cluster \
  --services innovatech-service \
  --query "services[0].runningCount"
```
