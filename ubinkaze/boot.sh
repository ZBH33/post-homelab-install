#!/bin/bash

set -euo pipefail

banner='▗▖ ▗▖▗▄▄▖ ▗▄▄▄▖▗▖  ▗▖▗▖ ▗▖ ▗▄▖ ▗▄▄▄▄▖▗▄▄▄▖
▐▌ ▐▌▐▌ ▐▌  █  ▐▛▚▖▐▌▐▌▗▞▘▐▌ ▐▌   ▗▞▘▐▌   
▐▌ ▐▌▐▛▀▚▖  █  ▐▌ ▝▜▌▐▛▚▖ ▐▛▀▜▌ ▗▞▘  ▐▛▀▀▘
▝▚▄▞▘▐▙▄▞▘▗▄█▄▖▐▌  ▐▌▐▌ ▐▌▐▌ ▐▌▐▙▄▄▄▖▐▙▄▄▖

'

echo -e "$banner"
echo "=> Ubinkaze is for fresh Ubuntu Server 24.04 installations only!"
echo "=> This is a modified script to help with ease of install!"
echo "=> Ubinkaze is for fresh Ubuntu Server 24.04 installations only!"
echo "=> Make sure to check out the OG; https://github.com/felipefontoura/ubinkaze.git"
echo -e "\nBegin installation (or abort with ctrl+c)..."

sudo apt-get update >/dev/null
sudo apt-get install -y git >/dev/null

echo "Getting things ready"
cd ~/post-homelab-install 
chmod +x intall.sh

echo "Installation starting..."
source ~/post-homelab-install/install.sh
