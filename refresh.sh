#!/bin/bash

BOOTSTRAPURL="https://github.com/bulwark-crypto/Bulwark/releases/download/1.3.0/bootstrap.dat.xz"
BOOTSTRAPARCHIVE="bootstrap.dat.xz"

clear
echo "This script will refresh your wallet."
read -p "Press Ctrl-C to abort or any other key to continue. " -n1 -s
clear

USER=$(whoami)

sudo systemctl stop bulwarkd

echo "Refreshing node, please wait."

sleep 5

sudo rm -Rf $HOME/.bulwark/blocks
sudo rm -Rf $HOME/.bulwark/database
sudo rm -Rf $HOME/.bulwark/chainstate
sudo rm -Rf $HOME/.bulwark/peers.dat

sudo cp $HOME/.bulwark/bulwark.conf $HOME/.bulwark/bulwark.conf.backup
sudo sed -i '/^addnode/d' $HOME/.bulwark/bulwark.conf

echo "Installing bootstrap file..."
wget $BOOTSTRAPURL && xz -cd $BOOTSTRAPARCHIVE > $HOME/.bulwark/bootstrap.dat && rm $BOOTSTRAPARCHIVE

sudo systemctl start bulwarkd

clear

echo "Your wallet is syncing. Please wait for this process to finish."
echo "This can take up to a few hours. Do not close this window." && echo ""

until [ -n "$(bulwark-cli getconnectioncount 2>/dev/null)"  ]; do
  sleep 1
done

until su -c "bulwark-cli mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null" bulwark; do
  echo -ne "Current block: "`su -c "bulwark-cli getinfo" bulwark | grep blocks | awk '{print $3}' | cut -d ',' -f 1`'\r'
  sleep 1
done

clear

echo "" && echo "Wallet refresh completed." && echo ""
