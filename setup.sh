#!/bin/bash

#turn off history logging
set +o history

# Set these to change the version of Bulwark to install

VPSTARBALLURL=`curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep linux64 | cut -d '"' -f 4`
VPSTARBALLNAME=`curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep linux64 | cut -d '"' -f 4 | cut -d "/" -f 9`
SHNTARBALLURL=`curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep ARMx64 | cut -d '"' -f 4`
SHNTARBALLNAME=`curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep ARMx64 | cut -d '"' -f 4 | cut -d "/" -f 9`
BWKVERSION=`curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep ARMx64 | cut -d '"' -f 4 | cut -d "/" -f 8`
BOOTSTRAPURL=`curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep bootstrap.dat.xz | grep browser_download_url | cut -d '"' -f 4`
BOOTSTRAPARCHIVE="bootstrap.dat.xz"

# Check if we have enough memory
if [[ `free -m | awk '/^Mem:/{print $2}'` -lt 850 ]]; then
  echo "This installation requires at least 1GB of RAM.";
  exit 1
fi

# Check if we have enough disk space
if [[ `df -k --output=avail / | tail -n1` -lt 10485760 ]]; then
  echo "This installation requires at least 10GB of free disk space.";
  exit 1
fi

clear
echo "This script will install a staking wallet."
read -p "Press Ctrl-C to abort or any other key to continue. " -n1 -s
clear

# Install tools for dig and systemctl
echo "Preparing installation..."
sudo apt-get install git dnsutils systemd -y > /dev/null 2>&1

# Make sure curl is installed
apt -qqy install curl
clear

# Check for systemd
sudo systemctl --version >/dev/null 2>&1 || { echo "systemd is required. Are you using Ubuntu 16.04?"  >&2; exit 1; }

# Get our current IP
if [ -z "$EXTERNALIP" ]; then
EXTERNALIP=`dig +short myip.opendns.com @resolver1.opendns.com`
fi
clear

USER=$(whoami)

# Generate random passwords
RPCUSER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
RPCPASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

# update packages and upgrade Ubuntu
echo "Installing dependencies..."
sudo apt-get -qq update
sudo apt-get -qq upgrade
sudo apt-get -qq autoremove
sudo apt-get -qq install wget htop xz-utils build-essential libtool autotools-dev autoconf automake libssl-dev libboost-all-dev software-properties-common
sudo add-apt-repository -y ppa:bitcoin/bitcoin
sudo apt update
sudo apt-get -qq install libdb4.8-dev libdb4.8++-dev libminiupnpc-dev libqt4-dev libprotobuf-dev protobuf-compiler libqrencode-dev git pkg-config libzmq3-dev aptitude

# Install Fail2Ban
sudo aptitude -y -q install fail2ban
# Reduce Fail2Ban memory usage - http://hacksnsnacks.com/snippets/reduce-fail2ban-memory-usage/
echo "ulimit -s 256" | sudo tee -a /etc/default/fail2ban
sudo service fail2ban restart


# Install UFW
sudo apt-get -qq install ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 52543/tcp
yes | sudo ufw enable

if [ -z $(cat /proc/cpuinfo | grep ARMv7) ]; then
  # Install Bulwark daemon for x86 systems
  wget $VPSTARBALLURL
  tar -xzvf $VPSTARBALLNAME && mv bin bulwark-$BWKVERSION
  rm $VPSTARBALLNAME
else
  # Install Bulwark daemon for ARMv7 systems
  wget $SHNTARBALLURL
  tar -xzvf $SHNTARBALLNAME && mv bin bulwark-$BWKVERSION
  rm $SHNTARBALLNAME
fi

sudo mv ./bulwark-$BWKVERSION/bulwarkd /usr/local/bin
sudo mv ./bulwark-$BWKVERSION/bulwark-cli /usr/local/bin
sudo mv ./bulwark-$BWKVERSION/bulwark-tx /usr/local/bin
rm -rf bulwark-$BWKVERSION

# Create .bulwark directory
mkdir $HOME/.bulwark

# Install bootstrap file
echo "Installing bootstrap file..."
wget $BOOTSTRAPURL && xz -cd $BOOTSTRAPARCHIVE > $HOME/.bulwark/bootstrap.dat && rm $BOOTSTRAPARCHIVE

# Create bulwark.conf
sudo tee > $HOME/.bulwark/bulwark.conf << EOL
${INSTALLERUSED}
rpcuser=${RPCUSER}
rpcpassword=${RPCPASSWORD}
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
logtimestamps=1
maxconnections=256
staking=1
EOL
chmod 0600 $HOME/.bulwark/bulwark.conf
chown -R $USER:$USER $HOME/.bulwark

sleep 5

sudo tee /etc/systemd/system/bulwarkd.service << EOL
[Unit]
Description=Bulwarks's distributed currency daemon
After=network.target
[Service]
Type=forking
User=${USER}
WorkingDirectory=${HOME}
ExecStart=/usr/local/bin/bulwarkd -conf=${HOME}/.bulwark/bulwark.conf -datadir=${HOME}/.bulwark
ExecStop=/usr/local/bin/bulwark-cli -conf=${HOME}/.bulwark/bulwark.conf -datadir=${HOME}/.bulwark stop
Restart=on-failure
RestartSec=1m
StartLimitIntervalSec=5m
StartLimitInterval=5m
StartLimitBurst=3
[Install]
WantedBy=multi-user.target
EOL
sudo systemctl enable bulwarkd
echo "Starting bulwarkd..."
sudo systemctl start bulwarkd

until [ -n "$(bulwark-cli getconnectioncount 2>/dev/null)"  ]; do
  sleep 1
done

if ! sudo systemctl status bulwarkd | grep -q "active (running)"; then
  echo "ERROR: Failed to start bulwarkd. Please contact support."
  exit
fi

echo "Waiting for wallet to load..."
until bulwark-cli getinfo 2>/dev/null | grep -q "version"; do
  sleep 1;
done

clear

echo "Your node has been set up, now setting up staking.."

sleep 5

#Ensure bulwarkd is active
  if sudo systemctl is-active --quiet bulwarkd; then
  	sudo systemctl start bulwarkd
fi
echo "Setting Up Staking Address.."

#Simple check to make sure the bulwarkd sync process is finished, so it isn't interrupted and forced to start over later.'
echo "Checking Bulwarkd status. The script will begin setting up staking once bulwarkd has finished syncing. Please allow this process to finish."
until bulwark-cli mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null; do
  echo -ne "Current block: "`bulwark-cli getinfo | grep blocks | awk '{print $3}' | cut -d ',' -f 1`'\r'
  sleep 1
done

#Ensure the .conf exists
touch $HOME/.bulwark/bulwark.conf

#If the line does not already exist, adds a line to bulwark.conf to instruct the wallet to stake

sed 's/staking=0/staking=1/' <$HOME/.bulwark/bulwark.conf

if grep -Fxq "staking=1" $HOME/.bulwark/bulwark.conf; then
  	echo "Staking Already Active"
  else
  	echo "staking=1" >> $HOME/.bulwark/bulwark.conf
fi

#Generates new address and assigns it a variable
STAKINGADDRESS=$(bulwark-cli getnewaddress)

#Ask for a password and apply it to a variable and confirm it.
ENCRYPTIONKEY=1
ENCRYPTIONKEYCONF=2
until [ $ENCRYPTIONKEY = $ENCRYPTIONKEYCONF ]; do
	read -e -s -p "Please enter a password to encrypt your new staking address/wallet with, you will not see what you type appear. (KEEP THIS SAFE, THIS CANNOT BE RECOVERED) : " ENCRYPTIONKEY
	read -e -s -p "Please confirm your password : " ENCRYPTIONKEYCONF
		if [ $ENCRYPTIONKEY != $ENCRYPTIONKEYCONF ]; then
			echo "Your passwords do not match, please try again."
		else
			echo "Password set."
		fi
done


#Encrypt the new address with the requested password
BIP38=$(bulwark-cli bip38encrypt $STAKINGADDRESS $ENCRYPTIONKEY)
echo "Address successfully encrypted!"

#Encrypt the wallet with the same password
bulwark-cli encryptwallet $ENCRYPTIONKEY && echo "Wallet successfully encrypted!" || { echo "Encryption failed!"; exit; }

#Wait for bulwarkd to close down after wallet encryption
echo "Waiting for bulwarkd to restart..."
until  ! systemctl is-active --quiet bulwarkd; do
    sleep 1
done

#Open up bulwarkd again
sudo systemctl start bulwarkd

#Unlocks the wallet for a long time period
bulwark-cli walletpassphrase $ENCRYPTIONKEY 9999999999 true

#Make decrypt script
sudo curl https://raw.githubusercontent.com/KaneoHunter/shn/master/decrypt.sh > /usr/local/bin/decrypt.sh
sudochown $USER:$USER /usr/local/bin/decrypt.sh
sudo chmod 700 /usr/local/bin/decrypt.sh

#create decrypt.sh and service

#Check if it already exists, remove if so.
if [  -e /$home/.bulwark/decrypt.sh ]; then
  rm -Rf /$home/.bulwark/decrypt.sh
fi

#create decrypt.sh
sudo tee > /$home/.bulwark/decrypt.sh << EOL
#!/bin/bash

#stop writing to history.
set +o history

#check bulwarkd is active. activate if not.
if [ -z "$(ps cax | grep bulwarkd)" ]; then
  systemctl start bulwarkd
fi

#ask for password.
read -e -s -p "Please enter a password to decrypt your staking wallet (Your password will not show as you type, this is normal) : " ENCRYPTIONKEY

#confirm wallet is synced. wait if not.
until bulwark-cli mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null; do
  echo -ne "Current block: "`bulwark-cli getinfo | grep blocks | awk '{print $3}' | cut -d ',' -f 1`'\r'
  sleep 1
done

#unlock wallet. confirm it's unlocked.
until [ -n $(bulwark-cli getstakingstatus | grep walletunlocked | grep false) ]; do

  #ask for password and attempt it
  read -e -s -p "Please enter a password to decrypt your staking wallet (Your password will not show as you type, this is normal) : " ENCRYPTIONKEY
  bulwark-cli walletpassphrase $ENCRYPTIONKEY 99999999 true
done

#tell user all was successful.
clear
echo "Wallet successfully unlocked!"
echo " "
bulwark-cli getstakingstatus

#restart history.
set -o history
EOL

#create decrypt service
sudo tee /etc/systemd/system/decryptwallet.service << EOL
[Unit]
Description=Runs a decryption script for your Bulwark wallet
[Service]
Type=oneshot
User=${USER}
ExecStart=/${home}/.bulwark/decrypt.sh
[Install]
WantedBy=multi-user.target
EOL

#Output more
cat << EOL
Your wallet has now been set up for staking, please send the coins you wish to
stake to ${STAKINGADDRESS}. Once your wallet is synced your coins should begin
staking automatically.

To check on the status of your staked coins you can run
"bulwark-cli getstakingstatus" and "bulwark-cli getinfo".

You can import the private key for this address in to your QT wallet using
the BIP38 tool under settings, just enter the information below with the
password you chose at the start. We recommend you take note of the following
lines to assist with recovery if ever needed.

${BIP38}

If your bulwarkd restarts, and you need to unlock your wallet again, use
the included script by running "systemctl start decryptwallet" to unlock your
wallet securely.

After the installation script ends, we will wipe all history and have no
storage record of your password, encrypted key, or addresses.
Any funds you lose access to are your own responsibility and the Bulwark team
will be unable to assist with their recovery. We therefore suggesting saving a
physical copy of this information.

If you have any concerns, we encourage you to contact us via any of our
social media channels.

EOL

read -e -p "Please confirm you have written down your password and encrypted key somewhere
safe by typing \"I have read the above and agree\" : " CONFIRMATION

until [  "$CONFIRMATION" = "I have read the above and agree"  ]; do
  if [  "$CONFIRMATION" != "I have read the above and agree"  ]; then
    read -e -p "Please confirm you have written down your password and encrypted key somewhere
    safe by typing \"I have read the above and agree\" : " CONFIRMATION

echo "Thank you for installing your Bulwark staking wallet, now finishing installation.."

unset CONFIRMATION ENCRYPTIONKEYCONF ENCRYPTIONKEY BIP38 STAKINGADDRESS

set -o history
clear

echo "Staking wallet operational."
