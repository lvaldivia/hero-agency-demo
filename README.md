# Hero Agency: demo de CI/CD con Azure DevOps

Demo en vivo de la charla **"Azure DevOps: del código a producción con CI/CD"**. El público escanea un QR y abre la app de producción en su celular. Cada deploy que pasa por el pipeline cambia lo que ven en su pantalla: el héroe, la versión y los colores. Si entra un villano, todos lo ven, y todos ven también el rollback.

## Qué hay en el repo

| Ruta | Para qué sirve |
| --- | --- |
| `src/server.js` | API Express: `/health`, `/api/version`, votación |
| `src/hero.js` | Lógica con la regla "Deku no pasa del 100%" (la que se rompe en la Misión 2) |
| `src/release.json` | La versión actual: héroe, quirk, colores |
| `releases/` | Versiones listas: `deku` (1.0.0), `todoroki` (1.1.0), `allmight` (1.2.0), `shigaraki` (6.6.6, villano) |
| `public/index.html` | La página que ve el público; se actualiza sola cada 5 s |
| `test/` | Tests con el runner nativo de Node (sin dependencias extra) |
| `azure-pipelines.yml` | Pipeline final: Build, Test, Staging, aprobación, Producción |
| `misiones/` | El YAML de cada misión, para copiar y pegar en vivo |
| `infra/setup-azure.sh` | Crea el App Service con slot de staging |
| `infra/rollback.sh` | Rollback con swap de slots (Misión 6) |
| `infra/reset-votos.sh` | Reinicia la votación antes de cada misión |

Comandos locales: `npm install`, `npm test`, `npm start` (abre http://localhost:3000) y `npm run release -- todoroki` para cambiar de héroe.

---

## Preparación (mínimo una semana antes)

### 1. Paralelismo de Azure Pipelines

Las organizaciones nuevas no tienen agentes Microsoft-hosted gratis por defecto. Pide el free grant con el formulario de Microsoft (demora unos días) o compra 1 job paralelo. Si no llega a tiempo, registra un agente self-hosted y cambia `vmImage: 'ubuntu-latest'` por `name: 'Default'` en el `pool`.

### 2. Organización, proyecto y repo

1. Crea el proyecto en Azure DevOps (por ejemplo, `HeroAgency`).
2. En **Repos**, importa este repo o súbelo con `git push`.

### 3. Infraestructura en Azure

```bash
az login
APP=hero-agency-luis ./infra/setup-azure.sh
```

El script crea el grupo de recursos, un plan S1 (los slots requieren Standard o superior), la web app, el slot `staging` y las variables `APP_ENV` como *slot settings*. Al final imprime las URLs y el `ADMIN_TOKEN`; copia las URLs en las variables de `azure-pipelines.yml` y guarda el token.

Si el nombre `hero-agency-luis` ya está tomado, usa otro y actualiza las variables `webAppName`, `stagingUrl` y `prodUrl`.

### 4. Service connection

**Project settings > Service connections > New > Azure Resource Manager**, con *Workload identity federation (automatic)*, limitado al grupo de recursos `rg-hero-agency`. Nómbrala `sc-hero-agency` (o cambia la variable `azureSubscription`).

### 5. Environments y aprobación

En **Pipelines > Environments** crea `staging` y `production`. En `production` entra a **Approvals and checks > Approvals** y agrega como aprobadores a ti y a la persona del público que aprobará en vivo. Esa persona debe estar invitada a la organización: pruébalo antes con su cuenta y su celular.

### 6. Primer run completo (obligatorio)

Crea el pipeline desde `azure-pipelines.yml` y córrelo completo una vez con Deku (1.0.0). En el primer run Azure pide permisos para usar el service connection y los environments: dale **Permit** ahora, no en plena charla. Al terminar, producción muestra a Deku v1.0.0.

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
3. Abre el run y lee el log en vivo mientras corre: instalación de Node, `npm ci`, artefacto publicado.

Mensaje: "el código ya no se compila en mi máquina, se compila igual siempre".

### Misión 2: El brazo roto (8 min)

1. Reemplaza el YAML con `misiones/mision-2-tests.yml` y haz commit. Corre en verde y aparece la pestaña **Tests**.
2. Abre la votación: "¿pasa o se rompe?".
3. En `src/hero.js`, cambia `return Math.max(0, Math.min(100, percent));` por `return percent;` y haz commit.
4. Falla el test "Deku nunca pasa del 100% (o se rompe los brazos)". Muestra la pestaña **Tests** con el error.
5. Señala que en el celular del público la app sigue igual: el bug nunca llegó a producción.
6. Revierte el cambio y haz commit para dejarlo en verde.

### Misión 3: Nadie entra a main sin permiso (8 min)

1. **Repos > Branches > main > Branch policies > Build validation**: agrega el pipeline como validación obligatoria.
2. Intenta un push directo a `main` desde tu terminal. Rebota con el error de política: léelo en voz alta.
3. Crea la rama `licencia-todoroki` con dos cambios:
   - `azure-pipelines.yml` con el contenido de `misiones/mision-5-produccion.yml`
   - `npm run release -- todoroki`
4. Abre el PR hacia `main`. La validación corre Build y Tests (Staging no corre porque no es `main`).
5. Cuando quede en verde, completa el PR. El merge dispara el pipeline completo.

### Misión 4: Primera patrulla en staging (12 min)

1. Mientras corre el stage Staging, explica el deploy al slot y el smoke test contra `/health`.
2. Cuando termine, abre la URL de staging en tu pantalla: cinta amarilla de STAGING y **Todoroki v1.1.0**.
3. Pide al público que mire su celular: siguen viendo a Deku v1.0.0 en producción.

Mensaje: "staging y producción conviven; nadie del público vio el cambio todavía".

### Misión 5: Licencia oficial (8 min)

1. El run queda en pausa esperando aprobación de `production`.
2. La persona del público aprueba desde su celular (le llega notificación por correo, o entra a la URL del run).
3. El swap de slots corre y, en unos segundos, todos los celulares muestran **"¡Nuevo deploy! v1.1.0"** y a Todoroki.
4. Explica que fue un blue/green: el código no se copió, solo se intercambiaron los slots.

Justo después de aprobar, deja en marcha la Misión 6 (siguiente sección), porque el villano necesita unos 8 minutos para llegar.

### Misión 6: Bonus Aizawa (5 min)

1. Crea la rama `ataque-villano`, corre `npm run release -- shigaraki`, haz commit y abre el PR con **auto-complete** activado.
2. Mientras viaja por el pipeline, haz el resumen del recorrido o adelanta preguntas.
3. Cuando pida aprobación, apruébalo tú. Los celulares cambian a **"¡Ataque villano!"** con Shigaraki v6.6.6.
4. Ejecuta `./infra/rollback.sh` (o el botón **Swap** del slot en el portal). Todoroki vuelve en segundos.

Mensaje: "los tests pasaron, pero la versión era mala; con slots, el rollback es un swap y no un nuevo deploy".

### Cierre

Muestra el historial del pipeline completo y el environment `production` con su historial de deploys. Plus Ultra.

---

## Plan B

| Si pasa esto | Haz esto |
| --- | --- |
| El YAML se rompe al editar | Copia el archivo de la misión desde `misiones/` |
| El run se queda en cola mucho tiempo | Muestra un run exitoso previo del historial y sigue con la explicación |
| Falla el deploy a Azure | Muestra la app con `npm start` en local y el run de la semana anterior |
| No llega la aprobación al celular del asistente | Apruébalo tú desde tu pantalla |
| El villano no llega a tiempo | Sáltalo y haz el rollback con la versión anterior: `./infra/rollback.sh` igual devuelve a Deku |
| Se cae el internet | Video grabado del demo completo |

## Después de la charla

```bash
az group delete -n rg-hero-agency --yes
```

El plan S1 cobra por hora mientras exista: bórralo apenas termines.
