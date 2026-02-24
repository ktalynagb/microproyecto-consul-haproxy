Vagrant.configure("2") do |config|
  config.ssh.insert_key = false
  config.vm.box = "ubuntu/focal64"

  # ===== web1 — Consul SERVER =====
  config.vm.define "web1" do |m|
    m.vm.hostname = "web1"
    m.vm.network "private_network", ip: "192.168.56.10"
    m.vm.provision "shell", path: "provision/common.sh"
    m.vm.provision "shell", path: "provision/consul.sh",
      args: ["web1","192.168.56.10","192.168.56.11","192.168.56.12","server"]
    m.vm.provision "shell", path: "provision/web.sh",
      args: ["web1","192.168.56.10"]
  end

  # ===== web2 — Consul SERVER =====
  config.vm.define "web2" do |m|
    m.vm.hostname = "web2"
    m.vm.network "private_network", ip: "192.168.56.11"
    m.vm.provision "shell", path: "provision/common.sh"
    m.vm.provision "shell", path: "provision/consul.sh",
      args: ["web2","192.168.56.11","192.168.56.10","192.168.56.12","server"]
    m.vm.provision "shell", path: "provision/web.sh",
      args: ["web2","192.168.56.11"]
  end

  # ===== haproxy — Consul CLIENT =====
  config.vm.define "haproxy" do |m|
    m.vm.hostname = "haproxy"
    m.vm.network "private_network", ip: "192.168.56.12"

    # Acceso desde tu PC
    m.vm.network "forwarded_port", guest: 80,   host: 8080, auto_correct: true
    m.vm.network "forwarded_port", guest: 8404, host: 8404, auto_correct: true
    m.vm.network "forwarded_port", guest: 8500, host: 8500, auto_correct: true

    m.vm.provision "shell", path: "provision/common.sh"
    m.vm.provision "shell", path: "provision/consul.sh",
      args: ["haproxy","192.168.56.12","192.168.56.10","192.168.56.11","client"]
    m.vm.provision "shell", path: "provision/haproxy.sh"
  end
end