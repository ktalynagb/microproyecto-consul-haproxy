#!/usr/bin/env bash
set -e

NODE_NAME="$1"
BIND_ADDR="$2"
JOIN1="$3"
JOIN2="$4"
# ── NUEVO: tipo de nodo ("server" o "client") ───────────────────────────────────
NODE_TYPE="${5:-server}"
# ────────────────────────────────────────────────────────────────────────────────
CONSUL_VERSION="1.18.1"

curl -fsSL -o /tmp/consul.zip "https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip"
sudo unzip -o /tmp/consul.zip -d /usr/local/bin
sudo chmod +x /usr/local/bin/consul

sudo useradd --system --home /etc/consul.d --shell /bin/false consul || true
sudo mkdir -p /etc/consul.d /opt/consul
sudo chown -R consul:consul /etc/consul.d /opt/consul

# ── CAMBIO: configuración condicional server vs client ──────────────────────────
if [ "${NODE_TYPE}" = "server" ]; then
  sudo tee /etc/consul.d/consul.hcl >/dev/null <<EOF
datacenter = "dc1"
node_name  = "${NODE_NAME}"
data_dir   = "/opt/consul"
bind_addr  = "${BIND_ADDR}"
client_addr = "0.0.0.0"

server           = true
bootstrap_expect = 2
retry_join       = ["${JOIN1}", "${JOIN2}"]

ui_config { enabled = true }
EOF
else
  # client (haproxy): solo necesita unirse al cluster para leer servicios
  sudo tee /etc/consul.d/consul.hcl >/dev/null <<EOF
datacenter  = "dc1"
node_name   = "${NODE_NAME}"
data_dir    = "/opt/consul"
bind_addr   = "${BIND_ADDR}"
client_addr = "0.0.0.0"

server     = false
retry_join = ["${JOIN1}", "${JOIN2}"]
EOF
fi
# ────────────────────────────────────────────────────────────────────────────────

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
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable consul
sudo systemctl restart consul
sleep 2
consul members || true