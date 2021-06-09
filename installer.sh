cd ~/
apt install sudo
wget -O- http://downloads-global.3cx.com/downloads/3cxpbx/public.key | sudo apt-key add
echo "deb http://downloads-global.3cx.com/downloads/debian stretch main" | sudo tee /etc/apt/sources.list.d/3cxpbx.list
sudo apt update
sudo apt install open-vm-tools
sudo apt install net-tools dphys-swapfile
sudo apt install 3cxpbx
echo 'sshd: ALL' >> /etc/hosts.deny
echo 'sshd: 79.10.156.226, 62.94.78.199, 185.203.88.0' >> /etc/hosts.allow
