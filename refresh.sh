#!/bin/bash

clear
echo "This script will refresh your wallet."
read -p "Press Ctrl-C to abort or any other key to continue. " -n1 -s
clear

if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root."
  exit 1
fi

USER=`ps u $(pgrep bulwarkd) | grep bulwarkd | cut -d " " -f 1`
USERHOME=`eval echo "~$USER"`

if [ -e /etc/systemd/system/bulwarkd.service ]; then
  systemctl stop bulwarkd
else
  su -c "bulwark-cli stop" $BWKUSER
fi

echo "Refreshing wallet, please wait."

sleep 5

rm -rf $USERHOME/.bulwark/blocks
rm -rf $USERHOME/.bulwark/database
rm -rf $USERHOME/.bulwark/chainstate
rm -rf $USERHOME/.bulwark/peers.dat

cp $USERHOME/.bulwark/bulwark.conf $USERHOME/.bulwark/bulwark.conf.backup
sed -i '/^addnode/d' $USERHOME/.bulwark/bulwark.conf

if [ -e /etc/systemd/system/bulwarkd.service ]; then
  sudo systemctl start bulwarkd
else
  su -c "bulwarkd -daemon" $USER
fi

echo "Your wallet is syncing. Please wait for this process to finish."
echo "This can take up to a few hours. Do not close this window." && echo ""

until [  $(bulwark-cli getconnectioncount) -gt 0  ] 2>/dev/nul; do
  sleep 1
done

until su -c "bulwark-cli mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null" $USER; do
  echo -ne "Current block: "`su -c "bulwark-cli getinfo" $USER | grep blocks | awk '{print $3}' | cut -d ',' -f 1`'\r'
  sleep 1
done

clear

echo "Your wallet has been refreshed, synced, and restarted!"
