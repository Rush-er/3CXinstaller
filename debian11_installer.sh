#!/bin/bash
cd ~/
sudo apt install apt-transport-https -y
sudo apt install gpg -y
sudo apt install net-tools dphys-swapfile -y
wget -O- https://repo.3cx.com/key.pub | gpg --dearmor | sudo tee /usr/share/keyrings/3cx-archive-keyring.gpg > /dev/null
/bin/echo "deb [arch=amd64 signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/3cx bullseye main" | sudo tee /etc/apt/sources.list.d/3cxpbx.list
sudo apt update
sudo apt install 3cxpbx
