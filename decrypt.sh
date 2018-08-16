#!/bin/bash

#stop writing to history.
set +o history

#check bulwarkd is active. activate if not.
if [ -z "$(ps cax | grep bulwarkd)" ]; then
  systemctl start bulwarkd

#ask for password.
read -e -s -p "Please enter a password to decrypt your staking wallet : " ENCRYPTIONKEY

#confirm wallet is synced. wait if not.
until bulwark-cli mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null; do
  echo -ne "Current block: "`bulwark-cli getinfo | grep blocks | awk '{print $3}' | cut -d ',' -f 1`'\r'
  sleep 1
done

#unlock wallet. confirm it's unlocked.
if [ -n $(bulwark-cli getstakingstatus | grep walletunlocked | grep false) ]; then
  bulwark-cli walletpassphrase $ENCRYPTIONKEY 99999999 true
else
  #tell user all was successful.
  clear
  echo "Wallet successfully unlocked!"
  echo " "
  bulwark-cli getstakingstatus

#restart history.
set -o history
