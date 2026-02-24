# 🚀 microproyecto-consul-haproxy

Laboratorio de infraestructura con **Vagrant + Consul + HAProxy + Node.js + Artillery**.  
Demuestra balanceo de carga automático, service discovery y pruebas de rendimiento.

---

## 🗺️ Arquitectura

```
Tu PC (host)
│
│  localhost:8080  →  HAProxy (VM: 192.168.56.12)
│  localhost:8404  →  HAProxy Stats
│  localhost:8500  →  Consul UI
│
│         HAProxy lee el catálogo de Consul vía consul-template
│         y balancea entre las réplicas Node.js
│
├── web1 (192.168.56.10)  — Consul SERVER + 3 réplicas Node.js (puertos 3001/3002/3003)
├── web2 (192.168.56.11)  — Consul SERVER + 3 réplicas Node.js (puertos 3001/3002/3003)
└── haproxy (192.168.56.12) — Consul CLIENT + HAProxy + consul-template
```

**Total: 6 instancias Node.js** balanceadas en round-robin a través de HAProxy.

---

## 📁 Estructura del repositorio

```
microproyecto-consul-haproxy/
│
├── Vagrantfile              # Define las 3 VMs y su aprovisionamiento
│
├── app/
│   ├── server.js            # App Node.js con Express (endpoints / y /health)
│   └── package.json         # Dependencias (express)
│
├── provision/
│   ├── common.sh            # Herramientas base: curl, unzip, net-tools
│   ├── consul.sh            # Instala Consul y lo configura como server o client
│   ├── web.sh               # Instala Node.js, copia la app y registra en Consul
│   └── haproxy.sh           # Instala HAProxy + consul-template + página 503
│
├── haproxy/
│   ├── haproxy.ctmpl        # Plantilla Consul Template que genera haproxy.cfg
│   └── 503.http             # Página personalizada cuando no hay backends
│
└── artillery/
    ├── low.yml              # Prueba de carga baja  (10 req/s · 60s)
    ├── medium.yml           # Prueba de carga media (50 req/s · 60s)
    └── high.yml             # Prueba de carga alta (200 req/s · 120s)
```

---

## ⚙️ Requisitos previos

Instalar en tu PC antes de empezar:

| Herramienta | Descarga |
|---|---|
| VirtualBox | https://www.virtualbox.org/wiki/Downloads |
| Vagrant | https://developer.hashicorp.com/vagrant/downloads |
| Node.js (para Artillery) | https://nodejs.org — versión LTS |

---

## 🏁 Levantar el entorno

```powershell
# 1. Clonar el repo y entrar a la carpeta
git clone https://github.com/ktalynagb/microproyecto-consul-haproxy.git
cd microproyecto-consul-haproxy

# 2. Cambiar a la rama de trabajo
git checkout DeivDevs

# 3. Levantar las 3 VMs (tarda ~10 min la primera vez)
vagrant up

# 4. Si las VMs ya existían y las volviste a encender:
vagrant up   # no re-aprovisiona, solo las enciende
```

> ⚠️ **Si cambias provision/consul.sh o el Vagrantfile** hay que destruir y recrear:
> ```powershell
> vagrant destroy -f
> vagrant up
> ```

---

## 🌐 Abrir las interfaces en el navegador

```powershell
# Aplicación web (balanceada por HAProxy)
Start-Process http://localhost:8080/

# Panel de estadísticas de HAProxy
Start-Process http://localhost:8404/

# Consul UI (ver nodos, servicios y health checks)
Start-Process http://localhost:8500/ui
```

---

## 🔍 Comandos de validación (Windows PowerShell)

### Ver miembros del cluster Consul

```powershell
vagrant ssh web1 -c "consul members"
```

**Para qué sirve:** Muestra los 3 nodos del cluster (web1 y web2 como *server*, haproxy como *client*) y confirma que todos están `alive`. Si alguno aparece como `failed` o `left`, el service discovery no funcionará correctamente.

---

### Demostrar balanceo round-robin

```powershell
1..6 | ForEach-Object { curl.exe -s http://localhost:8080/ | python -m json.tool | Select-String "instance" }
```

**Para qué sirve:** Hace 6 peticiones seguidas y muestra el campo `instance` de cada respuesta JSON. Deberías ver las 6 réplicas rotando en orden:
```
web1-3001 → web1-3002 → web1-3003 → web2-3001 → web2-3002 → web2-3003 → (repite)
```
Esto demuestra que HAProxy distribuye la carga entre todos los backends.

---

### Simular caída de web1 (alta disponibilidad)

```powershell
# Paso 1: Detener todas las réplicas de web1
vagrant ssh web1 -c "sudo systemctl stop webapp-3001 webapp-3002 webapp-3003"
```

**Para qué sirve:** Simula que el servidor web1 cae. Consul detecta el fallo en ~10 segundos (health check cada 5s). Después de eso, consul-template regenera `haproxy.cfg` automáticamente y HAProxy deja de enviar tráfico a web1. El sistema sigue funcionando solo con web2.

```powershell
# Verificar que solo responde web2 (volver a correr el round-robin)
1..6 | ForEach-Object { curl.exe -s http://localhost:8080/ | python -m json.tool | Select-String "instance" }
# Solo verás: web2-3001, web2-3002, web2-3003
```

---

### Simular caída total → ver página 503 personalizada

```powershell
# Detener también web2
vagrant ssh web2 -c "sudo systemctl stop webapp-3001 webapp-3002 webapp-3003"

# Esperar ~15 segundos y luego abrir en el navegador:
Start-Process http://localhost:8080/
```

**Para qué sirve:** Sin ningún backend disponible, HAProxy devuelve la página `503.http` personalizada en español: *"Servicio no disponible. En este momento no hay servidores disponibles. Intenta de nuevo."*

---

### Restaurar los servidores

```powershell
vagrant ssh web1 -c "sudo systemctl start webapp-3001 webapp-3002 webapp-3003"
vagrant ssh web2 -c "sudo systemctl start webapp-3001 webapp-3002 webapp-3003"
```

**Para qué sirve:** Vuelve a levantar las réplicas Node.js. Consul detecta que están `healthy` en ~10 segundos y consul-template los re-agrega automáticamente a HAProxy. El balanceo completo se restaura sin intervención manual.

---

## 🎯 Pruebas de rendimiento con Artillery

### Instalar Artillery (una sola vez en tu PC)

```powershell
npm install -g artillery
```

> Requiere Node.js instalado. Verificar con: `node --version`

---

### Correr los 3 escenarios

#### 🟢 Carga baja — 10 peticiones por segundo durante 60 segundos

```powershell
artillery run artillery/low.yml
```

**Para qué sirve:** Simula uso normal/ligero. Verifica que el sistema responde sin errores bajo carga cotidiana. Buena línea base para comparar.

---

#### 🟡 Carga media — 50 peticiones por segundo durante 60 segundos

```powershell
artillery run artillery/medium.yml
```

**Para qué sirve:** Simula un pico de tráfico moderado (por ejemplo, hora punta). Se puede observar cómo el balanceo distribuye la carga entre las 6 réplicas y si los tiempos de respuesta se mantienen estables.

---

#### 🔴 Carga alta — 200 peticiones por segundo durante 120 segundos

```powershell
artillery run artillery/high.yml
```

**Para qué sirve:** Simula estrés máximo. Permite ver el límite del sistema: cuándo empiezan a aparecer errores, cuánto sube la latencia y si alguna réplica empieza a fallar.

---

#### 📊 Generar reporte HTML (opcional pero muy visual)

```powershell
artillery run --output reporte-high.json artillery/high.yml
artillery report reporte-high.json
# Abre reporte-high.json.html en el navegador automáticamente
```

**Para qué sirve:** Genera una página HTML interactiva con gráficas de latencia, throughput y errores a lo largo del tiempo. Muy útil para presentar resultados.

---

## 🩺 Solución de problemas

### Las VMs no responden después de reiniciar el PC

```powershell
# Verificar estado
vagrant status

# Encenderlas (sin re-provisionar)
vagrant up
```

### El 503 que aparece no es el personalizado en español

Significa que HAProxy tiene una configuración inválida o que consul-template no ha regenerado el cfg todavía. Espera 15-20 segundos y recarga.

```powershell
# Verificar estado de servicios dentro de haproxy
vagrant ssh haproxy -c "sudo systemctl status consul consul-template haproxy"

# Forzar regeneración manual
vagrant ssh haproxy -c "sudo systemctl restart consul-template"
```

### Consul no muestra los servicios web

```powershell
# Verificar que las réplicas están corriendo
vagrant ssh web1 -c "sudo systemctl status webapp-3001 webapp-3002 webapp-3003"
vagrant ssh web2 -c "sudo systemctl status webapp-3001 webapp-3002 webapp-3003"

# Reiniciarlas si están caídas
vagrant ssh web1 -c "sudo systemctl restart webapp-3001 webapp-3002 webapp-3003"
vagrant ssh web2 -c "sudo systemctl restart webapp-3001 webapp-3002 webapp-3003"
```

---

## 📌 IPs y puertos de referencia rápida

| Recurso | Dirección desde el host |
|---|---|
| App web (via HAProxy) | http://localhost:8080 |
| HAProxy Stats | http://localhost:8404 |
| Consul UI | http://localhost:8500/ui |
| web1 (privada) | 192.168.56.10 |
| web2 (privada) | 192.168.56.11 |
| haproxy (privada) | 192.168.56.12 |
| Réplicas Node.js | :3001, :3002, :3003 en web1 y web2 |