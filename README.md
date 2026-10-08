# Hero Agency: CI/CD con Azure DevOps, paso a paso

Repositorio de la sesión **"Azure DevOps: del código a producción con CI/CD"**. Aquí está todo lo necesario para que armes el mismo demo en tu propia cuenta: una app con temática de My Hero Academia que viaja desde un commit hasta producción pasando por tests, una imagen Docker, staging, una aprobación y un rollback.

## Qué vas a construir

```
git push ──► Azure Repos ──► Azure Pipelines
                               │
                               ├─ 1. Build y Test: tests (pestaña Tests) + imagen Docker
                               │                    └─► Azure Container Registry (ACR)
                               ├─ 2. Staging: deploy a la Container App de staging + smoke test
                               ├─ 3. Aprobación manual (environment "production")
                               └─ 4. Producción: la MISMA imagen pasa a producción (blue/green)

Rollback: ./infra/rollback.sh mueve el tráfico a la revisión anterior en segundos
```

| Pieza | Servicio |
| --- | --- |
| Código | Azure Repos |
| Pipeline (YAML) | Azure Pipelines |
| Imágenes Docker | Azure Container Registry (Basic, sin usuario admin) |
| App de producción y de staging | Azure Container Apps (plan de consumo) |
| Acceso del pipeline a Azure | Service connections con Workload Identity Federation (sin contraseñas) |
| Acceso de la app al registro | Identidad administrada con rol AcrPull (sin contraseñas) |

## Lo que aprendes en cada misión

| Misión | Concepto | Archivo del pipeline |
| --- | --- | --- |
| 1. Despertar del Quirk | Integración continua: cada commit construye una imagen Docker | `misiones/mision-1-build.yml` |
| 2. El brazo roto | Tests automáticos: el código roto no avanza | `misiones/mision-2-tests.yml` |
| 3. Nadie entra a main sin permiso | Branch policies y Pull Requests | (se configura en Azure Repos) |
| 4. Primera patrulla en staging | Entrega continua y ambientes | `misiones/mision-4-staging.yml` |
| 5. Licencia oficial | Aprobación manual y blue/green | `misiones/mision-5-produccion.yml` |
| 6. Bonus Aizawa | Rollback instantáneo con revisiones | `infra/rollback.sh` |

---

## Requisitos

- Una **suscripción de Azure** donde seas Owner (o Contributor + User Access Administrator).
- Una **organización de Azure DevOps** (gratis): https://dev.azure.com
- **Azure CLI**: https://learn.microsoft.com/cli/azure/install-azure-cli
- **Docker Desktop**: https://www.docker.com/products/docker-desktop
- **Node.js 22** o superior y **Git**. En Windows usa **Git Bash** para correr los scripts.

**Costo aproximado:** unos $20–30 USD al mes mientras existan los recursos (Container Apps con 1 réplica siempre encendida + ACR Basic). Al terminar, bórralo todo con `./infra/cleanup.sh` (paso 10).

---

## Paso 1: Clona el repo y pruébalo en tu máquina

```bash
git clone https://github.com/lvaldivia/hero-agency-demo.git
cd hero-agency-demo
npm install
npm test          # 7 tests en verde
npm start         # abre http://localhost:3000
```

Con Docker:

```bash
docker build -t hero-agency .
docker run --rm -p 8080:8080 -e APP_ENV=local hero-agency
curl localhost:8080/health
```

El `Dockerfile` es multi-stage (`node:22-alpine`). La primera etapa instala dependencias y corre `npm test`, así que una imagen con tests rotos nunca se construye. La imagen final solo lleva lo necesario, corre sin usuario root y escucha en el puerto 8080.

Para cambiar de héroe: `npm run release -- todoroki` (las versiones están en `releases/`).

## Paso 2: Crea la infraestructura en Azure

Elige dos nombres únicos en todo Azure:

- `APP`: nombre de tu app. Solo minúsculas, números y guiones; por ejemplo `hero-agency-tunombre`.
- `ACR`: nombre de tu registro. Solo minúsculas y números; por ejemplo `acrheroagencytunombre`.

```bash
az login
APP=hero-agency-tunombre ACR=acrheroagencytunombre ./infra/setup-azure.sh
```

El script (tarda unos 10–20 minutos la primera vez):

1. Crea el grupo de recursos `rg-hero-agency` en `eastus2`. Puedes cambiarlo con `RG=...` y `LOCATION=...`.
2. Crea el **Azure Container Registry** Basic, sin usuario admin.
3. Construye la imagen en tu máquina y la sube con `az acr login`, que usa tu sesión de Azure y no una contraseña.
4. Crea el **Container Apps Environment** y dos apps:
   - `$APP-staging` con `APP_ENV=staging` (muestra una cinta amarilla STAGING).
   - `$APP` con `APP_ENV=production`, en modo *multiple revisions* para poder hacer rollback.
5. Le da a cada app una **identidad administrada** con rol **AcrPull** sobre el registro. Así la app baja su imagen sin contraseñas.
6. Guarda un `ADMIN_TOKEN` aleatorio como secreto (sirve para reiniciar la votación).

Al final imprime las **URLs** de producción y de staging y el **ADMIN_TOKEN**. Guárdalos: los usarás en el paso 6. No subas el token al repo.

> ¿Por qué Container Apps y no App Service? Los *deployment slots* de App Service necesitan un plan Standard o Premium, y muchas suscripciones nuevas tienen cuota 0 para esos planes. Container Apps logra lo mismo con revisiones y es más barato para un demo.

## Paso 3: Crea el proyecto en Azure DevOps e importa el código

1. En https://dev.azure.com, entra a tu organización y crea un proyecto: **New project**, nombre `HeroAgency`, visibilidad **Private**.
2. Ve a **Repos**. Como el repo está vacío, verás la opción **Import a repository**:
   - Clone URL: `https://github.com/lvaldivia/hero-agency-demo.git`
   - **Import**.
3. Clónalo en tu máquina; desde ahí harás los cambios de las misiones:
   ```bash
   git clone https://dev.azure.com/<tu-org>/HeroAgency/_git/HeroAgency
   ```

## Paso 4: Decide dónde corre el pipeline (agente)

Un **agente** es la máquina que ejecuta el pipeline. Tienes dos opciones:

**A) Agentes de Microsoft (Microsoft-hosted).** No instalas nada, pero las organizaciones nuevas no tienen agentes gratis activados. Pide el *free grant* en https://aka.ms/azpipelines-parallelism-request; Microsoft tarda de 2 a 3 días hábiles en aprobarlo. En el plan gratis un run puede esperar varios minutos en cola.

Si eliges esta opción, cambia el `pool` en `azure-pipelines.yml` y en todos los archivos de `misiones/`:

```yaml
pool:
  vmImage: 'ubuntu-latest'
```

**B) Agente self-hosted en tu laptop con Docker (sin cola).** Es la opción del repo, con `pool: name: 'Default'`.

1. Crea un **PAT**: **User settings → Personal access tokens → New Token**, con el scope **Agent Pools (Read & manage)** y una expiración corta.
2. Construye y registra el agente:
   ```bash
   docker build -t hero-agent:local infra/agente
   MSYS_NO_PATHCONV=1 docker run -d --name hero-agent --restart unless-stopped \
     -v hero-agent-data:/azp -v /var/run/docker.sock:/var/run/docker.sock \
     -e AZP_URL=https://dev.azure.com/<tu-org> -e AZP_TOKEN=<tu-PAT> -e AZP_AGENT_NAME=mi-laptop \
     hero-agent:local
   ```
3. Revisa en **Project settings → Agent pools → Default → Agents** que aparezca **Online**.
4. Opcional: el registro queda guardado en el volumen `hero-agent-data`, así que puedes recrear el contenedor sin el `-e AZP_TOKEN=...` para que el token no quede en su configuración.

El agente usa el Docker de tu máquina para construir las imágenes. Tu laptop debe estar encendida y con Docker Desktop abierto mientras corran los pipelines.

## Paso 5: Crea los service connections

Son los permisos del pipeline para entrar a Azure. Ve a **Project settings → Service connections → New service connection**.

**Azure Resource Manager**, para desplegar en Container Apps:

1. Elige **Azure Resource Manager** y luego **Workload Identity federation (automatic)**.
2. Llena:
   - Scope level: **Subscription**.
   - Subscription: la tuya.
   - Resource group: **rg-hero-agency**. Así el pipeline solo puede tocar ese grupo.
   - Service connection name: **`sc-hero-agency`**.
3. Deja **sin marcar** "Grant access permission to all pipelines". Lo autorizas para tu pipeline en el paso 7.

**Docker Registry**, para que la tarea `Docker@2` suba la imagen:

1. Elige **Docker Registry**, luego **Azure Container Registry**, y como autenticación **Workload Identity federation**.
2. Llena:
   - Subscription: la tuya.
   - Azure container registry: el que creaste en el paso 2.
   - Service connection name: **`sc-hero-agency-acr`**.

Si usas otros nombres, cambia las variables `azureSubscription` y `dockerRegistryServiceConnection` del YAML.

## Paso 6: Ajusta las variables del pipeline

Abre `azure-pipelines.yml` y **todos** los archivos de `misiones/`, y cambia estas variables por tus valores del paso 2:

| Variable | Valor |
| --- | --- |
| `containerRegistry` | `<tu-acr>.azurecr.io` |
| `containerAppName` | tu `APP` |
| `stagingAppName` | `<tu APP>-staging` |
| `resourceGroup` | `rg-hero-agency` (o el que hayas usado) |
| `stagingUrl` | la URL de staging que imprimió el script |
| `prodUrl` | la URL de producción que imprimió el script |

Haz commit y push a `main` en tu repo de Azure Repos.

## Paso 7: Environments, aprobación y primer run

1. En **Pipelines → Environments**, crea dos environments: **`staging`** y **`production`** (Resource: None).
2. En `production`, ve a **⋯ → Approvals and checks → + → Approvals**, agrégate como aprobador y haz clic en **Create**.
3. En **Pipelines → New pipeline**, elige **Azure Repos Git**, luego tu repo, luego **Existing Azure Pipelines YAML file**, y selecciona `/misiones/mision-5-produccion.yml`. Haz clic en **Run**.
   Para el primer run usa el pipeline completo, para dar todos los permisos de una vez.
4. En el primer run Azure DevOps pide permiso para usar los service connections, los environments y el pool. Haz clic en **View → Permit** en cada uno.
5. Cuando llegue a **Deploy a Producción**, apruébalo: **Review → Approve**.
6. Abre tu URL de producción: debe mostrar a **Deku v1.0.0**. En staging debe aparecer la cinta **STAGING**.
7. Para empezar las misiones, cambia la ruta del YAML: abre el pipeline, haz clic en **Edit**, luego en **⋯ → Settings** (arriba a la derecha), cambia "YAML file path" a `/azure-pipelines.yml` y guarda.

## Paso 8: Haz las misiones

El pipeline siempre lee **un solo archivo: `azure-pipelines.yml`**. Para avanzar de misión, copia el archivo de la misión encima de `azure-pipelines.yml`, haz commit y push, y espera el build.

Antes de cada votación puedes reiniciar los votos:

```bash
PROD_URL=<tu-url-de-produccion> ADMIN_TOKEN=<tu-token> ./infra/reset-votos.sh
```

### Misión 1: Despertar del Quirk (CI)

`azure-pipelines.yml` ya tiene la Misión 1: solo construye la imagen y la sube al ACR.

```bash
cp misiones/mision-1-build.yml azure-pipelines.yml
echo "# Misión 1" >> azure-pipelines.yml
git add azure-pipelines.yml
git commit -m "Misión 1: despertar del quirk"
git push
```

Abre el run: el commit lo disparó solo. En el paso **Construir y publicar imagen Docker** verás el build por etapas y el push con el número de build como tag.

### Misión 2: El brazo roto (tests)

```bash
cp misiones/mision-2-tests.yml azure-pipelines.yml
git add azure-pipelines.yml
git commit -m "Misión 2: el pipeline corre los tests"
git push
```

Cuando quede en verde, abre la pestaña **Tests** del run: verás 7 tests. Ahora rompe la regla de Deku y súbelo:

```bash
sed -i 's/return Math.max(0, Math.min(100, percent));/return percent;/' src/hero.js
git commit -am "Deku usa 120% de su poder"
git push
```

El run falla en **Ejecutar tests**, la pestaña Tests muestra los tests en rojo y la imagen no se construye: el bug no llega a producción. Revierte el cambio:

```bash
git revert --no-edit HEAD
git push
```

### Misión 3: Nadie entra a main sin permiso (branch policies)

1. Ve a **Repos → Branches → main → ⋯ → Branch policies → Build validation → +**. Elige tu pipeline, Trigger **Automatic**, Policy requirement **Required**, y haz clic en **Save**.
2. Intenta un push directo:
   ```bash
   echo "# Atajo" >> README.md
   git commit -am "Push directo a main"
   git push
   ```
   Rebota con `TF402455: Pushes to this branch are not permitted; you must use a pull request`. Deshaz el commit con `git reset --hard origin/main`.
3. Crea una rama con el pipeline completo y la versión de Todoroki:
   ```bash
   git checkout -b licencia-todoroki
   cp misiones/mision-5-produccion.yml azure-pipelines.yml
   npm run release -- todoroki
   git add azure-pipelines.yml src/release.json
   git commit -m "Licencia de Todoroki (v1.1.0)"
   git push -u origin licencia-todoroki
   ```
4. Abre un **Pull Request** hacia `main`. La validación corre Build y Test; Staging no corre porque la rama no es `main`.
5. Cuando quede en verde, haz clic en **Complete**. El merge dispara el pipeline completo.

### Misión 4: Primera patrulla en staging (CD)

El stage **Deploy a Staging** despliega la imagen recién construida en la app de staging y hace un *smoke test* contra `/health` con reintentos. Abre tu URL de staging: verás **Todoroki v1.1.0** con la cinta STAGING, mientras producción sigue mostrando a Deku.

### Misión 5: Licencia oficial (aprobación y blue/green)

El run se detiene en **Deploy a Producción** esperando la aprobación del environment `production`. Al aprobar, la **misma imagen** que se probó en staging se despliega en una revisión nueva de producción. El tráfico pasa a ella cuando está lista, y la revisión anterior queda viva, sin tráfico, para el rollback.

### Misión 6: Bonus Aizawa (rollback)

```bash
git checkout main && git pull
git checkout -b ataque-villano
npm run release -- shigaraki
git commit -am "Release v6.6.6"
git push -u origin ataque-villano
```

Abre el PR, complétalo y aprueba producción: aparece el villano Shigaraki v6.6.6. Su versión pasa todos los tests, pero es mala. Haz el rollback:

```bash
./infra/rollback.sh
```

El script mueve el 100 % del tráfico a la revisión anterior, y en segundos vuelve Todoroki. No hay reconstrucción ni redeploy. Si no usaste los nombres por defecto, pásale los tuyos: `APP=<tu-app> RG=<tu-rg> ./infra/rollback.sh`.

---

## Qué hay en el repo

| Ruta | Para qué sirve |
| --- | --- |
| `src/server.js` | API Express: `/health`, `/api/version` y la votación |
| `src/hero.js` | La regla "Deku no pasa del 100%" (la que se rompe en la Misión 2) |
| `src/release.json` | La versión actual: héroe, quirk, colores |
| `releases/` | Versiones listas: `deku` (1.0.0), `todoroki` (1.1.0), `allmight` (1.2.0), `shigaraki` (6.6.6, villano) |
| `public/index.html` | La página que ve el público; se actualiza sola cada 5 s |
| `test/` | 7 tests con el runner nativo de Node |
| `scripts/junit-reporter.js` | Reporter JUnit que la pestaña Tests de Azure Pipelines sí reconoce |
| `Dockerfile` | Imagen multi-stage: tests en el build, runtime sin root en el puerto 8080 |
| `azure-pipelines.yml` | El pipeline que lee Azure DevOps |
| `misiones/` | El YAML de cada misión |
| `infra/setup-azure.sh` | Crea ACR y Container Apps con identidad administrada |
| `infra/rollback.sh` | Rollback moviendo el tráfico a la revisión anterior |
| `infra/reset-votos.sh` | Reinicia la votación |
| `infra/cleanup.sh` | Borra todo el grupo de recursos |
| `infra/agente/` | Agente self-hosted de Azure Pipelines en Docker |

## Paso 9: Problemas comunes

| Problema | Solución |
| --- | --- |
| El run se queda en **Queued** | Agente Microsoft: espera el free grant o usa el agente self-hosted. Agente self-hosted: revisa que esté Online y que Docker Desktop esté abierto |
| "This pipeline needs permission to access a resource" | Abre el run y haz clic en **View → Permit** |
| Falla `Docker@2` con error de login | Revisa que el service connection Docker Registry apunte a tu ACR y se llame como la variable `dockerRegistryServiceConnection` |
| Falla el deploy a Container Apps | Revisa que `sc-hero-agency` tenga acceso al grupo de recursos y que `containerAppName` y `resourceGroup` sean los tuyos |
| La pestaña Tests no aparece | Debe existir `scripts/junit-reporter.js`; el pipeline usa `npm run test:ci` |
| En Windows, `az` falla con rutas raras | En Git Bash agrega `MSYS_NO_PATHCONV=1` antes del comando |
| `setup-azure.sh` falla en el nombre | `APP` y `ACR` deben ser únicos en Azure; prueba con otros |

## Paso 10: Limpieza (no lo olvides)

```bash
./infra/cleanup.sh            # borra el grupo de recursos completo
docker rm -f hero-agent       # si usaste el agente self-hosted
```

Después borra los service connections del proyecto y revoca el PAT que creaste.

Plus Ultra.
