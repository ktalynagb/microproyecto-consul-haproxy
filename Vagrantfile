require 'json'

# ── Leer configuración desde un único archivo ────────────────────────────────
cfg     = JSON.parse(File.read(File.join(__dir__, "provision/servers.json")))
SERVERS = cfg["servers"]                          # [{name, ip}, ...]
HAPROXY = cfg["haproxy"]                          # {name, ip}

# Todas las IPs del cluster (servers + haproxy) para retry_join
ALL_IPS = (SERVERS.map { |s| s["ip"] } + [HAPROXY["ip"]])

# bootstrap_expect = número de servers (se calcula solo)
BOOTSTRAP = SERVERS.length
# ─────────────────────────────────────────────────────────────────────────────

Vagrant.configure("2") do |config|
  config.ssh.insert_key = false
  config.vm.box         = "ubuntu/focal64"

  # ===== Nodos web (servers Consul) — se generan solos =====
  SERVERS.each do |srv|
    config.vm.define srv["name"] do |m|
      m.vm.hostname = srv["name"]
      m.vm.network "private_network", ip: srv["ip"]
      m.vm.provision "shell", path: "provision/common.sh"
      m.vm.provision "shell", path: "provision/consul.sh",
        # $1=name $2=ip $3=type $4=bootstrap_expect $4+N=peers
        args: [srv["name"], srv["ip"], "server", BOOTSTRAP.to_s] + ALL_IPS
      m.vm.provision "shell", path: "provision/web.sh",
        args: [srv["name"], srv["ip"]]
    end
  end

  # ===== HAProxy (client Consul) =====
  config.vm.define HAPROXY["name"] do |m|
    m.vm.hostname = HAPROXY["name"]
    m.vm.network "private_network", ip: HAPROXY["ip"]

    m.vm.network "forwarded_port", guest: 80,   host: 8080, auto_correct: true
    m.vm.network "forwarded_port", guest: 8404, host: 8404, auto_correct: true
    m.vm.network "forwarded_port", guest: 8500, host: 8500, auto_correct: true

    m.vm.provision "shell", path: "provision/common.sh"
    m.vm.provision "shell", path: "provision/consul.sh",
      # client no vota en raft, bootstrap_expect=0 (ignorado para clients)
      args: [HAPROXY["name"], HAPROXY["ip"], "client", "0"] + ALL_IPS
    m.vm.provision "shell", path: "provision/haproxy.sh"
  end
end