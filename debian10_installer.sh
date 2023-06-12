cd ~/
apt install sudo
sudo apt install gnupg2
wget -O- https://repo.3cx.com/key.pub | sudo apt-key add
echo "deb http://repo.3cx.com/3cx buster-testing main" | sudo tee /etc/apt/sources.list.d/3cxpbx.list
sudo apt update
sudo apt install open-vm-tools
sudo apt install net-tools dphys-swapfile
apt-cache policy 3cxpbx | grep -o '18.*' | grep -o '^\S*'
echo "Select the Version to intall [PRESS ENTER]: " 
read version
sudo apt install 3cxpbx=$version
