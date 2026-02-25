# 🚀 microproyecto-consul-haproxy

Laboratorio de infraestructura con **Vagrant · Consul · HAProxy · Node.js · Artillery**.

Demuestra de forma práctica cómo funcionan juntos el **service discovery**, el **balanceo de carga dinámico** y las **pruebas de rendimiento** en un entorno local reproducible al 100 %.

> **Rama activa de desarrollo:** `DeivDevs`

---

## 📖 ¿Qué hace este proyecto?

Cuando una empresa tiene una aplicación web con mucho tráfico, no puede depender de un solo servidor. Necesita varios servidores trabajando en paralelo y un componente que reparta las peticiones entre ellos. Pero además, si uno de esos servidores cae, el sistema debe detectarlo **solo** y dejar de enviarle tráfico **sin intervención humana**.

Este proyecto simula exactamente eso en tu propio PC:

1. **Varias réplicas de una app Node.js** corren en paralelo en máquinas virtuales separadas.
2. **Consul** actúa como "directorio telefónico" del cluster: sabe qué servicios existen, en qué IPs y puertos, y si están sanos.
3. **HAProxy** es el balanceador: recibe las peticiones del usuario y las reparte entre los servidores disponibles. Consul le dice en tiempo real cuáles están activos.
4. **Artillery** sirve para probar cuánta carga aguanta el sistema antes de degradarse.

---

## 🗺️ Arquitectura

```
Tu PC (host)
│
│  localhost:8080  ──►  HAProxy  (VM haproxy · 192.168.56.13)
│  localhost:8404  ──►  HAProxy Stats GUI
│  localhost:8500  ──►  Consul UI
│
│   HAProxy consulta el catálogo de Consul cada vez que un servidor
│   entra o sale, y actualiza su configuración automáticamente.
│
├── web1 (192.168.56.10)  — Consul SERVER + 3 réplicas Node.js (:3001 :3002 :3003)
├── web2 (192.168.56.11)  — Consul SERVER + 3 réplicas Node.js (:3001 :3002 :3003)
└── haproxy (192.168.56.13) — Consul CLIENT + HAProxy + consul-template
```

**Total: 6 instancias Node.js** balanceadas en round-robin a través de HAProxy.

### ¿Por qué 2 nodos Consul SERVER?

Consul usa un algoritmo de consenso llamado **Raft** para elegir un líder entre los servidores del cluster. Para tolerar la caída de 1 nodo y seguir funcionando se necesitan al menos **3 servidores** (quórum = mayoría). Con 2 servidores el cluster funciona pero no tolera fallos de quórum.

---

## 📁 Estructura del repositorio

```
microproyecto-consul-haproxy/
│
├── Vagrantfile                 # Orquestador: define las VMs, IPs y orden de aprovisionamiento
│
├── provision/
│   ├── servers.json            # ★ ÚNICA FUENTE DE VERDAD — IPs y nombres de todos los nodos
│   ├── common.sh               # Instala herramientas base en todas las VMs
│   ├── consul.sh               # Instala y configura Consul (server o client, dinámico)
│   ├── web.sh                  # Instala Node.js, despliega la app y registra servicios en Consul
│   └── haproxy.sh              # Instala HAProxy, consul-template y genera la config inicial
│
├── app/
│   ├── server.js               # Aplicación Node.js con Express
│   └── package.json            # Dependencias del proyecto Node.js
│
├── haproxy/
│   ├── haproxy.ctmpl           # Plantilla dinámica que consul-template convierte en haproxy.cfg
│   └── 503.http                # Página de error personalizada cuando no hay backends disponibles
│
└── artillery/
    ├── low.yml                 # Escenario de carga baja   (10 req/s · 60 s)
    ├── medium.yml              # Escenario de carga media  (50 req/s · 60 s)
    └── high.yml                # Escenario de carga alta  (200 req/s · 120 s)
```

---

## 🔬 Qué hace cada módulo en detalle

### `Vagrantfile` — el orquestador

Es el archivo que le dice a Vagrant qué máquinas virtuales crear, con qué IPs y en qué orden ejecutar los scripts de configuración. Lee `provision/servers.json` para saber cuántos nodos web crear, sus nombres e IPs. Esto hace que agregar o quitar servidores no requiera tocar el Vagrantfile.

Cada VM pasa por tres scripts en orden:
```
common.sh → consul.sh → web.sh      (para nodos web)
common.sh → consul.sh → haproxy.sh  (para el balanceador)
```

---

### `provision/servers.json` — única fuente de verdad ★

Este archivo es la **única pieza que hay que modificar** para cambiar la topología del cluster. Define:
- Los nodos `consul_servers`: VMs que ejecutan la app Node.js Y participan en el quórum de Consul.
- Los nodos `app_clients` (opcional): VMs que solo ejecutan la app, se unen al cluster como clients. **Estos sí pueden agregarse en caliente** con `vagrant up appN` sin destruir nada.
- El nodo `haproxy`: el balanceador.

---

### `provision/common.sh` — herramientas base

Se ejecuta en **todas** las VMs antes que cualquier otro script. Instala las utilidades del sistema operativo que los demás scripts necesitan: `curl`, `unzip`, `net-tools` y `jq`. Sin este script, `consul.sh` no podría descargar el binario de Consul.

---

### `provision/consul.sh` — instalación dinámica de Consul

Es el script más inteligente del proyecto. Recibe como argumentos el nombre del nodo, su IP, el tipo (`server` o `client`), el número de servidores para el quórum y **todas las IPs del cluster como lista variable**.

Con esos datos **construye automáticamente** el `consul.hcl` correcto para cada nodo:
- Si es `server`: activa el modo servidor, establece el quórum y lista todos los peers para `retry_join`.
- Si es `client`: se une al cluster sin participar en el quórum raft.
El script también crea y activa el servicio `systemd` para que Consul arranque automáticamente con la VM.

---

### `provision/web.sh` — despliegue de la aplicación

Se ejecuta en cada nodo web. Hace tres cosas:

1. **Instala Node.js 18** vía el repositorio oficial de NodeSource.
2. **Despliega la app**: copia `server.js` y `package.json` a `/opt/webapp` e instala las dependencias.
3. **Crea 3 servicios systemd** (`webapp-3001`, `webapp-3002`, `webapp-3003`) y **3 archivos de registro en Consul** para que Consul sepa que este nodo ofrece el servicio `web` en esos puertos con un health check HTTP en `/health`.

---

### `app/server.js` — la aplicación Node.js

Una API REST minimalista construida con Express que expone dos endpoints:

| Endpoint | Respuesta | Para qué sirve |
|---|---|---|
| `GET /` | JSON con hostname, puerto, pid, timestamp e instancia | Demostrar el balanceo (cada respuesta viene de una réplica diferente) |
| `GET /health` | `200 OK` con `{ status: "healthy" }` | Health check que usan Consul y HAProxy para saber si la réplica está viva |

La app lee su configuración desde variables de entorno (`PORT`, `NAME`), lo que permite que la misma base de código corra como múltiples réplicas con identidades diferentes.

---

### `provision/haproxy.sh` — instalación del balanceador

Instala y configura la capa de balanceo completa:

1. Instala `haproxy` desde los repositorios de Ubuntu.
2. Descarga e instala `consul-template`.
3. Copia la plantilla `haproxy.ctmpl` y la página `503.http` a sus rutas definitivas.
4. Crea un script `wait-consul.sh` que espera a que el cluster tenga un líder antes de continuar.
5. **Genera el `haproxy.cfg` inicial de forma síncrona** (`consul-template -once`) antes de arrancar HAProxy, evitando que arranque con una configuración inválida.
6. Registra `consul-template` como servicio systemd para actualizaciones automáticas en background.

---

### `haproxy/haproxy.ctmpl` — plantilla de configuración dinámica

Plantilla en Go Templates que `consul-template` procesa. Cada vez que Consul detecta un cambio en el servicio `web`, consul-template renderiza esta plantilla y recarga HAProxy sin interrumpir conexiones activas.

- Si hay servidores `healthy` → los lista como backends activos con health check.
- Si no hay ninguno → activa un backend dummy y HAProxy devuelve la página `503.http` personalizada.

---

### `haproxy/503.http` — página de error personalizada

Respuesta HTTP completa (cabeceras + cuerpo HTML) que HAProxy sirve cuando no hay ningún backend disponible. Está en español e indica al usuario que el servicio no está disponible temporalmente.

---

### `artillery/*.yml` — escenarios de prueba de carga

| Archivo | Usuarios/s | Duración | Propósito |
|---|---|---|---|
| `low.yml` | 10 | 60 s | Línea base, uso normal |
| `medium.yml` | 50 | 60 s | Pico de tráfico moderado |
| `high.yml` | 200 | 120 s | Estrés máximo, buscar el límite |

---

## ⚙️ Requisitos previos

| Herramienta | Para qué sirve | Descarga |
|---|---|---|
| VirtualBox | Motor de virtualización que corre las VMs | https://www.virtualbox.org/wiki/Downloads |
| Vagrant | Gestiona el ciclo de vida de las VMs | https://developer.hashicorp.com/vagrant/downloads |
| Node.js LTS | Necesario para ejecutar Artillery | https://nodejs.org |

---

## 🏁 Levantar el entorno por primera vez

```powershell
# 1. Clonar el repositorio
git clone https://github.com/ktalynagb/microproyecto-consul-haproxy.git
cd microproyecto-consul-haproxy

# 2. Cambiar a la rama de desarrollo
git checkout DeivDevs

# 3. Levantar todas las VMs y aprovisionarlas (primera vez: ~10-15 min)
vagrant up
```

> ⚠️ **Si cambiaste consul.sh, Vagrantfile o servers.json** es obligatorio destruir y recrear:
> ```powershell
> vagrant destroy -f
> vagrant up
> ```

> ✅ **Si solo apagaste el PC** (VMs en estado saved o poweroff):
> ```powershell
> vagrant up   # las enciende sin re-provisionar
> ```

---

## 🌐 Abrir las interfaces en el navegador

```powershell
# Aplicación web balanceada por HAProxy
Start-Process http://localhost:8080/

# Panel de estadísticas de HAProxy (backends, tráfico, estado)
Start-Process http://localhost:8404/

# Consul UI (nodos del cluster, servicios registrados, health checks)
Start-Process http://localhost:8500/ui
```

---

## 🔍 Comandos de validación en Windows PowerShell

### 1. Ver el estado del cluster Consul

```powershell
vagrant ssh web1 -c "consul members"
```

**Qué hace:** Consulta al agente Consul de `web1` la lista de todos los nodos del cluster. Debes ver `web1` y `web2` como `server alive` y `haproxy` como `client alive`. Si alguno aparece como `failed` o `left`, el service discovery no funcionará y HAProxy no tendrá backends.

---

### 2. Demostrar el balanceo round-robin

```powershell
1..6 | ForEach-Object { curl.exe -s http://localhost:8080/ | python -m json.tool | Select-String "instance" }
```

**Qué hace:** Envía 6 peticiones seguidas al balanceador y extrae el campo `instance` de cada respuesta JSON. Deberías ver las 6 réplicas rotando:
```
web1-3001 → web1-3002 → web1-3003 → web2-3001 → web2-3002 → web2-3003 → (repite)
```
Esto prueba que HAProxy está distribuyendo la carga equitativamente entre todos los backends activos.

---

### 3. Simular caída de un servidor (alta disponibilidad)

```powershell
# Detener todas las réplicas de web1
vagrant ssh web1 -c "sudo systemctl stop webapp-3001 webapp-3002 webapp-3003"

# Verificar que ahora solo responde web2
1..6 | ForEach-Object { curl.exe -s http://localhost:8080/ | python -m json.tool | Select-String "instance" }
# Resultado esperado: solo verás web2-3001, web2-3002, web2-3003
```

**Qué hace:** Simula que el servidor `web1` falla completamente. Consul detecta el fallo en ~10 s, consul-template regenera `haproxy.cfg` y HAProxy deja de enviar tráfico a `web1` de forma automática.

---

### 4. Simular caída total → activar la página 503 personalizada

```powershell
# Detener también web2
vagrant ssh web2 -c "sudo systemctl stop webapp-3001 webapp-3002 webapp-3003"

# Esperar ~15 segundos y abrir en el navegador
Start-Process http://localhost:8080/
```

**Qué hace:** Con todos los backends caídos, HAProxy devuelve la página `503.http` personalizada en español en lugar del error genérico.

---

### 5. Restaurar todos los servidores

```powershell
vagrant ssh web1 -c "sudo systemctl start webapp-3001 webapp-3002 webapp-3003"
vagrant ssh web2 -c "sudo systemctl start webapp-3001 webapp-3002 webapp-3003"
```

**Qué hace:** Vuelve a levantar las réplicas Node.js en ambos nodos. Consul detecta que los health checks pasan en ~10 s, consul-template re-agrega los servidores a HAProxy y el balanceo completo se restaura sin ninguna intervención adicional.

---

## 📈 Escalabilidad — agregar servidores

| Tipo de nodo | ¿En caliente? | Cómo |
|---|---|---|
| `consul_servers` (web1, web2...) | ❌ Requiere `vagrant destroy -f` | Edita `servers.json` y recrea |
| `app_clients` (appN adicionales) | ✅ Sí, en caliente | Agrega a `servers.json` + `vagrant up appN` |

**Para agregar un nuevo servidor** (si requiere destroy): editar `provision/servers.json`, agregar el nuevo nodo y ejecutar:

```powershell
vagrant destroy -f
vagrant up
```

El Vagrantfile, `consul.sh` y `web.sh` se adaptan solos al nuevo número de nodos. **No hay que modificar ningún otro archivo.**

---

## 🎯 Pruebas de rendimiento con Artillery

```powershell
# Instalar Artillery (una sola vez en tu PC)
npm install -g artillery

# Verificar instalación
artillery version

# Escenario 1: carga baja (10 req/s · 60 s)
artillery run artillery/low.yml

# Escenario 2: carga media (50 req/s · 60 s)
artillery run artillery/medium.yml

# Escenario 3: carga alta (200 req/s · 120 s)
artillery run artillery/high.yml

# Generar reporte HTML visual
artillery run --output reporte.json artillery/high.yml
artillery report reporte.json
# Abre reporte.json.html en el navegador con gráficas interactivas
```

---

## 🩺 Solución de problemas frecuentes

### Las VMs no responden al abrir el PC

```powershell
vagrant status
vagrant up
```

### La GUI de HAProxy no abre (localhost:8404)

```powershell
vagrant ssh haproxy -c "sudo systemctl status haproxy"
vagrant ssh haproxy -c "cat /etc/haproxy/haproxy.cfg"
vagrant ssh haproxy -c "sudo systemctl restart consul-template"
```

### La GUI de Consul no abre (localhost:8500/ui)

```powershell
vagrant ssh haproxy -c "sudo systemctl status consul"
vagrant ssh haproxy -c "sudo journalctl -u consul -n 50"
```

### HAProxy devuelve 503 genérico (sin la página en español)

Significa que `haproxy.cfg` tiene un error de sintaxis o que consul-template no pudo regenerarlo.

```powershell
vagrant ssh haproxy -c "sudo haproxy -c -f /etc/haproxy/haproxy.cfg"
vagrant ssh haproxy -c "sudo journalctl -u consul-template -n 30"
```

### Los servicios web no aparecen en Consul tras reiniciar las VMs

```powershell
vagrant ssh web1 -c "sudo systemctl restart webapp-3001 webapp-3002 webapp-3003"
vagrant ssh web2 -c "sudo systemctl restart webapp-3001 webapp-3002 webapp-3003"
```

---

## 📌 Referencia rápida de IPs y puertos

| Recurso | Dirección desde el host |
|---|---|
| App web (via HAProxy) | http://localhost:8080 |
| HAProxy Stats GUI | http://localhost:8404 |
| Consul UI | http://localhost:8500/ui |
| web1 (IP privada) | 192.168.56.10 |
| web2 (IP privada) | 192.168.56.11 |
| haproxy (IP privada) | 192.168.56.13 |
| Réplicas Node.js | :3001, :3002, :3003 en cada nodo web |
