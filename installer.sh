cd ~/
apt install sudo
wget -O- http://downloads-global.3cx.com/downloads/3cxpbx/public.key | sudo apt-key add
echo "deb http://downloads-global.3cx.com/downloads/debian stretch main" | sudo tee /etc/apt/sources.list.d/3cxpbx.list
sudo apt update
sudo apt install net-tools dphys-swapfile
sudo apt install 3cxpbx
sudo apt install open-vm-tools
