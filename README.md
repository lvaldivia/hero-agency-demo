# Hero Agency: demo de CI/CD con Azure DevOps

Demo en vivo de la charla **"Azure DevOps: del código a producción con CI/CD"**. El público escanea un QR y abre la app de producción en su celular. Cada deploy que pasa por el pipeline cambia lo que ven en su pantalla: el héroe, la versión y los colores. Si entra un villano, todos lo ven, y todos ven también el rollback.

La app corre como **contenedor Docker** en **Azure Container Apps**. El pipeline construye la imagen una sola vez, la sube a **Azure Container Registry (ACR)** y esa misma imagen viaja de staging a producción. Las apps jalan la imagen con **identidad administrada** y el pipeline se autentica con **Workload Identity Federation**: no hay contraseñas en ningún lado.

## Qué hay en el repo

| Ruta | Para qué sirve |
| --- | --- |
| `src/server.js` | API Express: `/health`, `/api/version`, votación |
| `src/hero.js` | Lógica con la regla "Deku no pasa del 100%" (la que se rompe en la Misión 2) |
| `src/release.json` | La versión actual: héroe, quirk, colores |
| `releases/` | Versiones listas: `deku` (1.0.0), `todoroki` (1.1.0), `allmight` (1.2.0), `shigaraki` (6.6.6, villano) |
| `public/index.html` | La página que ve el público; se actualiza sola cada 5 s |
| `test/` | Tests con el runner nativo de Node (sin dependencias extra) |
| `Dockerfile` | Multi-stage `node:22-alpine`: instala y corre `npm test`; la imagen final solo lleva lo necesario, corre sin root en el puerto 8080 |
| `scripts/junit-reporter.js` | Reporter JUnit que la pestaña **Tests** de Azure Pipelines sí reconoce |
| `azure-pipelines.yml` | Pipeline final: Build y Test (imagen al ACR), Staging, aprobación, Producción |
| `misiones/` | El YAML de cada misión, para copiar y pegar en vivo |
| `infra/setup-azure.sh` | Crea ACR, Container Apps Environment y las apps de staging y producción |
| `infra/rollback.sh` | Rollback moviendo el tráfico a la revisión anterior (Misión 6) |
| `infra/reset-votos.sh` | Reinicia la votación antes de cada misión |
| `infra/cleanup.sh` | Borra todo el grupo de recursos después de la charla |
| `infra/agente/` | Agente self-hosted de Azure Pipelines en Docker (sin cola en vivo) |

Comandos locales: `npm install`, `npm test`, `npm start` (abre http://localhost:3000) y `npm run release -- todoroki` para cambiar de héroe.

Con Docker:

```bash
docker build -t hero-agency .
docker run --rm -p 8080:8080 -e APP_ENV=local hero-agency
curl localhost:8080/health
```

## Arquitectura

| Pieza | Recurso | Nota |
| --- | --- | --- |
| Registro de imágenes | ACR Basic `acrheroagencyluis` | Sin admin user |
| Producción | Container App `hero-agency-luis` | `APP_ENV=production`, modo *multiple revisions* |
| Staging | Container App `hero-agency-luis-staging` | `APP_ENV=staging` (cinta amarilla) |
| Entorno | Container Apps Environment `cae-hero-agency` | Plan de consumo, sin Log Analytics |
| Pull de imágenes | Identidad administrada *system-assigned* de cada app | Rol **AcrPull** sobre el ACR |
| Identidad del pipeline | Identidad administrada *user-assigned* `id-hero-agency-pipelines` | **Contributor** solo sobre `rg-hero-agency` y **AcrPush** sobre el ACR |

Cada app corre **una sola réplica** porque los votos viven en memoria.

Container Apps no tiene *deployment slots*. Staging y producción son dos apps separadas, y así `APP_ENV` queda fijo en cada una, como un *slot setting*. Producción usa revisiones: cada deploy crea una revisión nueva que recibe el 100 % del tráfico, y la anterior queda viva para el rollback.

---

## Preparación (mínimo una semana antes)

### 1. Paralelismo de Azure Pipelines

El pipeline corre en un **agente self-hosted** (pool `Default`) dentro de un contenedor en tu laptop. Así no hay cola: con el plan gratis de agentes Microsoft-hosted un run puede esperar varios minutos antes de empezar, y eso en vivo es silencio. Además, el build reutiliza la caché de Docker.

```bash
docker build -t hero-agent:local infra/agente
# Primera vez: registra el agente (PAT con Agent Pools: Read & manage)
docker run -d --name hero-agent --restart unless-stopped \
  -v hero-agent-data:/azp -v /var/run/docker.sock:/var/run/docker.sock \
  -e AZP_URL=https://dev.azure.com/<org> -e AZP_TOKEN=<PAT> -e AZP_AGENT_NAME=laptop hero-agent:local
# Luego recrea el contenedor sin AZP_TOKEN: la configuración queda en el volumen hero-agent-data
```

Requisitos el día de la charla: Docker Desktop abierto y la laptop con internet. En **Project settings > Agent pools > Default** el agente debe verse *Online*.

Plan B sin laptop: en el `pool` cambia `name: 'Default'` por `vmImage: 'ubuntu-latest'`. Las organizaciones nuevas necesitan el free grant de Microsoft (https://aka.ms/azpipelines-parallelism-request; demora unos días) o 1 job paralelo comprado.

### 2. Organización, proyecto y repo

1. Crea el proyecto en Azure DevOps (por ejemplo, `HeroAgency`).
2. En **Repos**, crea el repo y súbelo con `git push`.

### 3. Infraestructura en Azure

```bash
az login
APP=hero-agency-luis ACR=acrheroagencyluis ./infra/setup-azure.sh
```

El script hace lo siguiente:

1. Crea el grupo de recursos y el ACR Basic sin admin user.
2. Construye la imagen localmente y la sube con `az acr login` (tu sesión de Azure, sin contraseña) como `hero-agency:inicial`.
3. Crea el Container Apps Environment y las dos apps con identidad administrada, `--registry-identity system` (el rol AcrPull se asigna solo), `ADMIN_TOKEN` como secreto y `APP_ENV` fijo.

Al final imprime las URLs y el `ADMIN_TOKEN`. Copia las URLs en `stagingUrl` y `prodUrl` del pipeline y de `misiones/`, y guarda el token fuera del repo.

Se usa Container Apps y no App Service porque los slots de App Service requieren un plan Standard o Premium, y suscripciones nuevas suelen tener cuota 0 para esos planes.

### 4. Service connections (Workload Identity Federation)

Se necesitan dos:

| Nombre | Tipo | Para qué |
| --- | --- | --- |
| `sc-hero-agency` | Azure Resource Manager | Desplegar en Container Apps (`AzureContainerApps@1`, `AzureCLI@2`) |
| `sc-hero-agency-acr` | Docker Registry → Azure Container Registry | `Docker@2 buildAndPush` |

Ambas son de tipo **Workload identity federation (manual)** y usan la identidad `id-hero-agency-pipelines`. El acceso queda limitado porque esa identidad solo tiene Contributor en `rg-hero-agency` y AcrPush en el ACR. Por cada service connection hay una *federated credential* en la identidad, con el *issuer* y el *subject* que muestra Azure DevOps al crearla.

Si prefieres el portal: **Project settings > Service connections > New > Azure Resource Manager > Workload identity federation (automatic)**, limitado al grupo `rg-hero-agency`. Para el ACR: **Docker Registry > Azure Container Registry > Workload Identity federation**.

### 5. Environments y aprobación

En **Pipelines > Environments** crea `staging` y `production`. En `production` entra a **Approvals and checks > Approvals** y agrega como aprobadores a ti y a la persona del público que aprobará en vivo. Esa persona debe estar invitada a la organización: pruébalo antes con su cuenta y su celular.

### 6. Primer run completo (obligatorio)

Crea el pipeline desde `azure-pipelines.yml` y córrelo completo una vez con Deku (1.0.0). Autoriza para el pipeline los dos service connections y los dos environments, desde **Security / Pipeline permissions** de cada recurso o con **Permit** en el primer run, para que no pida permisos en plena charla. Al terminar, producción muestra a Deku v1.0.0.

### 7. QR

Genera el QR apuntando a `prodUrl` y ponlo en la lámina "Escanea el demo". La URL de staging solo se muestra en tu pantalla.

---

## Estado inicial (el día de la charla)

- Producción muestra a **Deku v1.0.0**.
- En `main`, `azure-pipelines.yml` tiene el contenido de `misiones/mision-1-build.yml` (haz ese commit antes de subir al escenario).
- `main` **no** tiene branch policies todavía.
- En el navegador: pestañas abiertas con el repo, el pipeline, la app de producción y la de staging.
- Fuente grande en VS Code y navegador al 125–150 %.

---

## Guion en vivo

Antes de cada misión con votación: `PROD_URL=... ADMIN_TOKEN=... ./infra/reset-votos.sh`

### Misión 0: Presentación del examen (2 min)

Muestra la lámina del QR y espera a que el público vea a Deku en su celular. Explica las reglas: "yo doy el examen, ustedes son el jurado y votan desde su celular".

### Misión 1: Despertar del Quirk (7 min)

1. Abre `azure-pipelines.yml` en Repos y recorre el YAML: `trigger`, `stages`, `jobs`, `steps`.
2. Haz un cambio mínimo (por ejemplo, un comentario) y commit a `main`.
3. Abre el run y lee el log en vivo mientras corre: `docker build` por etapas y el push de la imagen al ACR con el número de build como tag.

Mensaje: "el código ya no se compila en mi máquina, se compila igual siempre, y lo que sale es una imagen que corre igual en cualquier lado".

Si alguien pregunta: el `Dockerfile` también corre `npm test` en su primera etapa, así que una imagen con tests rotos nunca se construye. La Misión 2 los saca a un paso visible del pipeline.

### Misión 2: El brazo roto (8 min)

1. Reemplaza el YAML con `misiones/mision-2-tests.yml` y haz commit. Corre en verde y aparece la pestaña **Tests**.
2. Abre la votación: "¿pasa o se rompe?".
3. En `src/hero.js`, cambia `return Math.max(0, Math.min(100, percent));` por `return percent;` y haz commit.
4. Falla el test "Deku nunca pasa del 100% (o se rompe los brazos)". Muestra la pestaña **Tests** con el error y que la imagen Docker ni siquiera se construyó.
5. Señala que en el celular del público la app sigue igual: el bug nunca llegó a producción.
6. Revierte el cambio y haz commit para dejarlo en verde.

### Misión 3: Nadie entra a main sin permiso (8 min)

1. **Repos > Branches > main > Branch policies > Build validation**: agrega el pipeline como validación obligatoria.
2. Intenta un push directo a `main` desde tu terminal. Rebota con el error de política: léelo en voz alta.
3. Crea la rama `licencia-todoroki` con dos cambios:
   - `azure-pipelines.yml` con el contenido de `misiones/mision-5-produccion.yml`
   - `npm run release -- todoroki`
4. Abre el PR hacia `main`. La validación corre Build y Test (Staging no corre porque no es `main`).
5. Cuando quede en verde, completa el PR. El merge dispara el pipeline completo.

### Misión 4: Primera patrulla en staging (12 min)

1. Mientras corre el stage Staging, explica el deploy de la imagen recién construida a la app de staging y el smoke test contra `/health`.
2. Cuando termine, abre la URL de staging en tu pantalla: cinta amarilla de STAGING y **Todoroki v1.1.0**.
3. Pide al público que mire su celular: siguen viendo a Deku v1.0.0 en producción.

Mensaje: "staging y producción conviven; nadie del público vio el cambio todavía".

### Misión 5: Licencia oficial (8 min)

1. El run queda en pausa esperando aprobación de `production`.
2. La persona del público aprueba desde su celular (le llega notificación por correo, o entra a la URL del run).
3. Se promueve la imagen y, en unos segundos, todos los celulares muestran **"¡Nuevo deploy! v1.1.0"** y a Todoroki.
4. Explica que fue un blue/green: no se reconstruyó nada. La **misma imagen** que se probó en staging se desplegó en una revisión nueva de producción, y el tráfico pasó a ella cuando estuvo lista. La revisión de Deku sigue viva, sin tráfico.

Justo después de aprobar, deja en marcha la Misión 6 (siguiente sección), porque el villano necesita unos 8 minutos para llegar.

### Misión 6: Bonus Aizawa (5 min)

1. Crea la rama `ataque-villano`, corre `npm run release -- shigaraki`, haz commit y abre el PR con **auto-complete** activado.
2. Mientras viaja por el pipeline, haz el resumen del recorrido o adelanta preguntas.
3. Cuando pida aprobación, apruébalo tú. Los celulares cambian a **"¡Ataque villano!"** con Shigaraki v6.6.6.
4. Ejecuta `./infra/rollback.sh`. También puedes hacerlo en el portal: Container App de producción → **Revisions and replicas** → 100 % de tráfico a la revisión anterior. Todoroki vuelve en segundos.

Mensaje: "los tests pasaron, pero la versión era mala; con revisiones, el rollback es mover el tráfico y no un nuevo deploy".

### Cierre

Muestra el historial del pipeline completo y el environment `production` con su historial de deploys. Plus Ultra.

---

## Plan B

| Si pasa esto | Haz esto |
| --- | --- |
| El YAML se rompe al editar | Copia el archivo de la misión desde `misiones/` |
| El run se queda en cola mucho tiempo | Muestra un run exitoso previo del historial y sigue con la explicación |
| Falla el deploy a Azure | Muestra la app con `docker run` en local y el run de la semana anterior |
| No llega la aprobación al celular del asistente | Apruébalo tú desde tu pantalla |
| El villano no llega a tiempo | Sáltalo y haz el rollback con la versión anterior: `./infra/rollback.sh` igual devuelve a Deku |
| Se cae el internet | Video grabado del demo completo |

## Después de la charla

```bash
./infra/cleanup.sh
```

Borra el grupo de recursos completo (ACR, Container Apps y la identidad del pipeline). Después borra los service connections de Azure DevOps (quedan apuntando a recursos que ya no existen) y revoca cualquier PAT que hayas creado para la preparación.
