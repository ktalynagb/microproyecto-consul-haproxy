#!/usr/bin/env bash
set -e
NODELABEL="$1"
NODEIP="$2"

curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

sudo mkdir -p /opt/webapp
sudo cp /vagrant/app/server.js /opt/webapp/server.js

REPLICAS=(3001 3002 3003)

for PORT in "${REPLICAS[@]}"; do
  SVC="webapp-${PORT}"

  sudo tee "/etc/systemd/system/${SVC}.service" >/dev/null <<EOF
[Unit]
Description=Node ${SVC}
After=network.target consul.service
Wants=consul.service

[Service]
Environment=PORT=${PORT}
Environment=NAME=${NODELABEL}-${PORT}
WorkingDirectory=/opt/webapp
ExecStart=/usr/bin/node /opt/webapp/server.js
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

  sudo tee "/etc/consul.d/${SVC}.json" >/dev/null <<EOF
{
  "service": {
    "name": "web",
    "id": "${NODELABEL}-${PORT}",
    "address": "${NODEIP}",
    "port": ${PORT},
    "checks": [
      { "http": "http://${NODEIP}:${PORT}/health", "interval": "5s", "timeout": "2s" }
    ]
  }
}
EOF
done

sudo systemctl daemon-reload
for PORT in "${REPLICAS[@]}"; do
  sudo systemctl enable "webapp-${PORT}"
  sudo systemctl restart "webapp-${PORT}"
done

sudo systemctl restart consul
sleep 2
consul catalog services || true