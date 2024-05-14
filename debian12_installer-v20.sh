#!/bin/bash
cd ~/
apt install jq curl wget sudo apt-transport-https gpg net-tools -y
wget -O- http://repo.3cx.com/key.pub | gpg --dearmor | sudo tee /usr/share/keyrings/3cx-archive-keyring.gpg > /dev/null
/bin/echo "deb [arch=amd64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/debian/2000 bookworm main"  	>> /etc/apt/sources.list
/bin/echo "deb [arch=amd64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/debian-security/2000 bookworm-security main" >> /etc/apt/sources.list
/bin/echo "deb [arch=amd64 by-hash=yes signed-by=/usr/share/keyrings/3cx-archive-keyring.gpg] http://repo.3cx.com/3cx bookworm main"  			> /etc/apt/sources.list.d/3cxpbx.list
apt update
apt install postgresql-15 postgresql-client-15 nginx -y
apt-cache policy 3cxpbx | grep -o '20.*' | grep -o '^\S*'
echo "Select the Version to intall, write the full version number then PRESS ENTER: " 
read version
sudo apt install 3cxpbx=$version
