#!/bin/bash
cd ~/
wget -O- https://repo.3cx.com/key.pub | sudo apt-key add
echo "deb http://repo.3cx.com/3cx bullseye main" | sudo tee /etc/apt/sources.list.d/3cxpbx.list
sudo apt update
sudo apt install apt-transport-https -y
sudo apt install gpg -y
sudo apt install net-tools -y
sudo apt install nginx -y
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl reload nginx
apt-chache policy 3cxpbx | grep -o '18.*' | grep -o '^\S*'
echo "Select the Version to intall [PRESS ENTER]: " 
read version
sudo apt install 3cxpbx=$version
