1. Creamos el repo en GitHub (microproyecto-consul-haproxy) y ya se ven las carpetas (app/, provision/, haproxy/, artillery/).

2. En este momento, tu Vagrantfile todavía está usando provision inline (comandos escritos dentro del Vagrantfile), por eso las carpetas existen pero Vagrant aún no las está usando. El siguiente paso es conectar esas carpetas al Vagrantfile con provisioning por path: y ejecutar vagrant provision (HOY 22/02/2026)


OBJETIVOS :

- web1 y web2: corren la app NodeJS (servidores web).

- haproxy: corre HAProxy (balanceador) y expone su stats/GUI.

- Consul: corre en nodos (mínimo en web1/web2) para service discovery (que HAProxy “descubra” servidores disponibles).

- Artillery: corre pruebas de carga desde el host para medir respuesta del sistema


CÓDIGOS:

1. Vagrantfile

Es el orquestador local, define:

- Qué VMs existen (web1, web2, haproxy)

- Qué box usan (ubuntu/focal64)

- Qué IP privada tiene cada una (192.168.56.x)

- Cómo se aprovisionan (por ahora inline)

- Cómo se accede por SSH

Nota: config.ssh.insert_key = false se usó para evitar los problemas de llaves SSH desincronizadas que te estaban bloqueando la entrada.


2. Provision:

- Aquí van los scripts de aprovisionamiento (automatización).

- Antes con inline (menos ordenado).

- Con scripts, el repo queda limpio y replicable: cualquiera del grupo corre vagrant up y queda igual.

- common.sh: utilidades base (curl, unzip, net-tools…)

- consul.sh: instala y configura Consul + servicio systemd

- web.sh: instala NodeJS, copia la app y levanta réplicas + registra en Consul

- haproxy.sh: instala HAProxy, stats, página 503 y consul-template


3. app:

- Aquí va el código de la aplicación NodeJS. NO HAY
- Esta app es la que se va a replicar en web1 y web2 (varios puertos) para demostrar escalabilidad. NO HAY


4. haproxy:

- Aquí va la configuración del balanceador. YA HAY

- haproxy.cfg o plantilla (haproxy.ctmpl) si se usa service discovery con Consul. YA HAY

- 503.http: una página personalizada para cuando no haya backends disponibles. YA HAY


5. artillery:

- Aquí van los archivos YAML de pruebas de carga (bajo/medio/alto). NO HAY


En qué continuar:

Pasar de provisioning inline a provisioning por scripts:

- Crear los scripts reales en provision (ya)

- Modificar el Vagrantfile para que llame esos scripts con path (ya).

Ejecutar (ya):

- vagrant provision web1 (ya)

- vagrant provision web2 (ya)

- vagrant provision haproxy (ya)

Verificar desde el host:

- http://localhost:8080 (app vía HAProxy)

- http://localhost:8404 (stats HAProxy)


