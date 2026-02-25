#!/usr/bin/env bash
set -e

NODE_NAME="$1"
BIND_ADDR="$2"
NODE_TYPE="$3"           # "server" o "client"
BOOTSTRAP_EXPECT="$4"   # número de servers (calculado en Vagrantfile)
shift 4                  # elimina los 4 primeros args
PEER_IPS=("$@")         # todas las IPs restantes como array

CONSUL_VERSION="1.18.1"

# ── Instalar Consul ────────────────────────────────────────────────────────────
curl -fsSL -o /tmp/consul.zip \
  "https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip"
sudo unzip -o /tmp/consul.zip -d /usr/local/bin
sudo chmod +x /usr/local/bin/consul

sudo useradd --system --home /etc/consul.d --shell /bin/false consul || true
sudo mkdir -p /etc/consul.d /opt/consul
sudo chown -R consul:consul /etc/consul.d /opt/consul

# ── Construir el array retry_join en formato HCL ───────────────────────────────
RETRY_JOIN_HCL=""
for ip in "${PEER_IPS[@]}"; do
  # No incluirse a sí mismo en el retry_join
  if [ "$ip" != "$BIND_ADDR" ]; then
    RETRY_JOIN_HCL="${RETRY_JOIN_HCL}\"${ip}\", "
  fi
done
# Quitar la coma y espacio del final
RETRY_JOIN_HCL="[${RETRY_JOIN_HCL%, }]"

# ── Escribir consul.hcl según el tipo de nodo ──────────────────────────────────
if [ "${NODE_TYPE}" = "server" ]; then
  sudo tee /etc/consul.d/consul.hcl >/dev/null <<EOF
datacenter = "dc1"
node_name  = "${NODE_NAME}"
data_dir   = "/opt/consul"
bind_addr  = "${BIND_ADDR}"
client_addr = "0.0.0.0"

server           = true
bootstrap_expect = ${BOOTSTRAP_EXPECT}
retry_join       = ${RETRY_JOIN_HCL}

ui_config { enabled = true }
EOF
else
  sudo tee /etc/consul.d/consul.hcl >/dev/null <<EOF
datacenter  = "dc1"
node_name   = "${NODE_NAME}"
data_dir    = "/opt/consul"
bind_addr   = "${BIND_ADDR}"
client_addr = "0.0.0.0"

server     = false
retry_join = ${RETRY_JOIN_HCL}

ui_config { enabled = true }
EOF
fi

# ── Servicio systemd ───────────────────────────────────────────────────────────
sudo tee /etc/systemd/system/consul.service >/dev/null <<'EOF'
[Unit]
Description=Consul Agent
Wants=network-online.target
After=network-online.target

[Service]
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable consul
sudo systemctl restart consul
sleep 5
consul members || true