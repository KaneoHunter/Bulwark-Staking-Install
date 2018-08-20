#!/bin/bash

VPSTARBALLURL=`curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep linux64 | cut -d '"' -f 4`
VPSTARBALLNAME=`curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep linux64 | cut -d '"' -f 4 | cut -d "/" -f 9`
SHNTARBALLURL=`curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep ARM | cut -d '"' -f 4`
SHNTARBALLNAME=`curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep ARM | cut -d '"' -f 4 | cut -d "/" -f 9`
BWKVERSION=`curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep ARM | cut -d '"' -f 4 | cut -d "/" -f 8`
BOOTSTRAPURL=`curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep bootstrap.dat.xz | grep browser_download_url | cut -d '"' -f 4`
BOOTSTRAPARCHIVE="bootstrap.dat.xz"

CHARS="/-\|"

# Make sure curl is installed
apt -qqy install curl
clear

clear
echo "This script will update your wallet to version $BWKVERSION"
read -p "Press Ctrl-C to abort or any other key to continue. " -n1 -s
clear

if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root."
  exit 1
fi

USER=`ps u $(pgrep bulwarkd) | grep bulwarkd | cut -d " " -f 1`
USERHOME=`eval echo "~$USER"`

echo "Shutting down wallet..."
if [ -e /etc/systemd/system/bulwarkd.service ]; then
  systemctl stop bulwarkd
else
  su -c "bulwark-cli stop" $USER
fi

if [ -z $(cat /proc/cpuinfo | grep ARMv7) ]; then
  # Install Bulwark daemon for x86 systems
  wget $VPSTARBALLURL
  tar -xzvf $VPSTARBALLNAME && mv bin bulwark-$BWKVERSION
  rm $VPSTARBALLNAME
  cp ./bulwark-$BWKVERSION/bulwarkd /usr/local/bin
  cp ./bulwark-$BWKVERSION/bulwark-cli /usr/local/bin
  cp ./bulwark-$BWKVERSION/bulwark-tx /usr/local/bin
  rm -rf bulwark-$BWKVERSION
else
  # Install Bulwark daemon for ARMv7 systems
  wget $SHNTARBALLURL
  tar -xzvf $SHNTARBALLNAME && mv bin bulwark-$BWKVERSION
  rm $SHNTARBALLNAME
  cp ./bulwark-$BWKVERSION/bulwarkd /usr/local/bin
  cp ./bulwark-$BWKVERSION/bulwark-cli /usr/local/bin
  cp ./bulwark-$BWKVERSION/bulwark-tx /usr/local/bin
  rm -rf bulwark-$BWKVERSION
fi

if [ -e /usr/bin/bulwarkd ];then rm -rf /usr/bin/bulwarkd; fi
if [ -e /usr/bin/bulwark-cli ];then rm -rf /usr/bin/bulwark-cli; fi
if [ -e /usr/bin/bulwark-tx ];then rm -rf /usr/bin/bulwark-tx; fi

# Remove addnodes from bulwark.conf
sed -i '/^addnode/d' $USERHOME/.bulwark/bulwark.conf

# Install bootstrap file
echo "Installing bootstrap file..."
wget $BOOTSTRAPURL && xz -cd $BOOTSTRAPARCHIVE > $HOME/.bulwark/bootstrap.dat && rm $BOOTSTRAPARCHIVE

# Add Fail2Ban memory hack if needed
if ! grep -q "ulimit -s 256" /etc/default/fail2ban; then
  echo "ulimit -s 256" | sudo tee -a /etc/default/fail2ban
  systemctl restart fail2ban
fi

echo "Restarting Bulwark daemon..."
if [ -e /etc/systemd/system/bulwarkd.service ]; then
  systemctl disable bulwarkd
  rm /etc/systemd/system/bulwarkd.service
fi

cat > /etc/systemd/system/bulwarkd.service << EOL
[Unit]
Description=Bulwarks's distributed currency daemon
After=network.target
[Service]
Type=forking
User=${USER}
WorkingDirectory=${USERHOME}
ExecStart=/usr/local/bin/bulwarkd -conf=${USERHOME}/.bulwark/bulwark.conf -datadir=${USERHOME}/.bulwark
ExecStop=/usr/local/bin/bulwark-cli -conf=${USERHOME}/.bulwark/bulwark.conf -datadir=${USERHOME}/.bulwark stop
Restart=on-failure
RestartSec=1m
StartLimitIntervalSec=5m
StartLimitInterval=5m
StartLimitBurst=3
[Install]
WantedBy=multi-user.target
EOL
sudo systemctl enable bulwarkd
sudo systemctl start bulwarkd

until [ -n "$(bulwark-cli getconnectioncount 2>/dev/null)"  ]; do
  sleep 1
done

clear

echo "Your wallet is syncing. Please wait for this process to finish."

until su -c "bulwark-cli mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null" $USER; do
  for (( i=0; i<${#CHARS}; i++ )); do
    sleep 2
    echo -en "${CHARS:$i:1}" "\r"
  done
done

clear

echo "Your wallet is now up to date!"
