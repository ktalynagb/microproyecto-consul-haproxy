Vagrant.configure("2") do |config|
  config.ssh.insert_key = false
  # Máquina Web1
  config.vm.define "web1" do |web1|
    web1.vm.box = "ubuntu/focal64"
    web1.vm.hostname = "web1"
    web1.vm.network "private_network", ip: "192.168.56.10"
    web1.vm.provision "shell", inline: <<-SHELL
      apt-get update
      apt-get install -y nodejs npm consul
      echo "Servidor web1 listo"
    SHELL
  end

  # Máquina Web2
  config.vm.define "web2" do |web2|
    web2.vm.box = "ubuntu/focal64"
    web2.vm.hostname = "web2"
    web2.vm.network "private_network", ip: "192.168.56.11"
    web2.vm.provision "shell", inline: <<-SHELL
      apt-get update
      apt-get install -y nodejs npm consul
      echo "Servidor web2 listo"
    SHELL
  end

  # Máquina HAProxy
  config.vm.define "haproxy" do |haproxy|
    haproxy.vm.box = "ubuntu/focal64"
    haproxy.vm.hostname = "haproxy"
    haproxy.vm.network "private_network", ip: "192.168.56.12"
    haproxy.vm.provision "shell", inline: <<-SHELL
      apt-get update
      apt-get install -y haproxy
      echo "Balanceador HAProxy listo"
    SHELL
  end

end
