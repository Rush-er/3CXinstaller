#!/bin/bash
cd ~/
sudo apt install apt-transport-https -y
sudo apt install gpg -y
sudo apt install net-tools -y
wget -O- https://repo.3cx.com/key.pub | sudo apt-key add
echo "deb http://repo.3cx.com/3cx bullseye main" | sudo tee /etc/apt/sources.list.d/3cxpbx.list
sudo apt update
sudo apt install 3cxpbx
