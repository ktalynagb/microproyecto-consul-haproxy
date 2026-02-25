#!/usr/bin/env bash
set -e

sudo apt-get install -y haproxy

CT_VERSION="0.37.4"
curl -fsSL -o /tmp/ct.zip "https://releases.hashicorp.com/consul-template/${CT_VERSION}/consul-template_${CT_VERSION}_linux_amd64.zip"
sudo unzip -o /tmp/ct.zip -d /usr/local/bin
sudo chmod +x /usr/local/bin/consul-template

sudo mkdir -p /etc/haproxy/errors
sudo cp /vagrant/haproxy/503.http  /etc/haproxy/errors/503.http
sudo cp /vagrant/haproxy/haproxy.ctmpl /etc/haproxy/haproxy.ctmpl

# ── Script de espera al líder Consul ──────────────────────────────────────────
sudo tee /usr/local/bin/wait-consul.sh >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
echo "Esperando líder Consul..."
til curl -sf http://127.0.0.1:8500/v1/status/leader 2>/dev/null | grep -q '"'; do
  sleep 2
done
echo "Consul listo."
SCRIPT
sudo chmod +x /usr/local/bin/wait-consul.sh
# ──────────────────────────────────────────────────────────────────────────────

sudo tee /etc/systemd/system/consul-template.service >/dev/null <<'EOF'
[Unit]
Description=Consul Template
After=network-online.target consul.service
Wants=network-online.target consul.service

[Service]
ExecStartPre=/usr/local/bin/wait-consul.sh
ExecStart=/usr/local/bin/consul-template \
  -consul-addr=127.0.0.1:8500 \
  -template "/etc/haproxy/haproxy.ctmpl:/etc/haproxy/haproxy.cfg:systemctl reload haproxy"
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable haproxy consul-template

# ── BUG FIX: generar haproxy.cfg inicial ANTES de arrancar HAProxy ─────────────
/usr/local/bin/wait-consul.sh
/usr/local/bin/consul-template \
  -once \
  -consul-addr=127.0.0.1:8500 \
  -template "/etc/haproxy/haproxy.ctmpl:/etc/haproxy/haproxy.cfg"
# ──────────────────────────────────────────────────────────────────────────────

sudo systemctl restart haproxy
sudo systemctl start consul-template