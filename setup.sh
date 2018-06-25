#!/bin/bash

# Set these to change the version of Bulwark to install

VPSTARBALLURL="https://github.com/bulwark-crypto/Bulwark/releases/download/1.3.0/bulwark-1.3.0.0-linux64.tar.gz"
VPSTARBALLNAME="bulwark-1.3.0.0-linux64.tar.gz"
SHNTARBALLURL="https://github.com/bulwark-crypto/Bulwark/releases/download/1.3.0/bulwark-1.3.0.0-ARMx64.tar.gz"
SHNTARBALLNAME="bulwark-1.3.0.0-ARMx64.tar.gz"
BWKVERSION="1.3.0.0"
BOOTSTRAPURL="https://github.com/bulwark-crypto/Bulwark/releases/download/1.3.0/bootstrap.dat.xz"
BOOTSTRAPARCHIVE="bootstrap.dat.xz"

# Check if we are root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root." 1>&2
   exit 1
fi

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

# Install tools for dig and systemctl
echo "Preparing installation..."
apt-get install git dnsutils systemd -y > /dev/null 2>&1

# Check for systemd
systemctl --version >/dev/null 2>&1 || { echo "systemd is required. Are you using Ubuntu 16.04?"  >&2; exit 1; }

# Get our current IP
if [ -z "$EXTERNALIP" ]; then
EXTERNALIP=`dig +short myip.opendns.com @resolver1.opendns.com`
fi
clear

USER=root
USERHOME=`eval echo "~$USER"`

# Generate random passwords
RPCUSER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
RPCPASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

# update packages and upgrade Ubuntu
echo "Installing dependencies..."
apt-get -qq update
apt-get -qq upgrade
apt-get -qq autoremove
apt-get -qq install wget htop xz-utils
apt-get -qq install build-essential && apt-get -qq install libtool autotools-dev autoconf automake && apt-get -qq install libssl-dev && apt-get -qq install libboost-all-dev && apt-get -qq install software-properties-common && add-apt-repository -y ppa:bitcoin/bitcoin && apt update && apt-get -qq install libdb4.8-dev && apt-get -qq install libdb4.8++-dev && apt-get -qq install libminiupnpc-dev && apt-get -qq install libqt4-dev libprotobuf-dev protobuf-compiler && apt-get -qq install libqrencode-dev && apt-get -qq install git && apt-get -qq install pkg-config && apt-get -qq install libzmq3-dev
apt-get -qq install aptitude

# Install Fail2Ban
aptitude -y -q install fail2ban
# Reduce Fail2Ban memory usage - http://hacksnsnacks.com/snippets/reduce-fail2ban-memory-usage/
echo "ulimit -s 256" | sudo tee -a /etc/default/fail2ban
service fail2ban restart


# Install UFW
apt-get -qq install ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 52543/tcp
yes | ufw enable

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

  # Create .bulwark directory
mkdir $USERHOME/.bulwark

# Install bootstrap file
echo "Installing bootstrap file..."
wget $BOOTSTRAPURL && xz -cd $BOOTSTRAPARCHIVE > $USERHOME/.bulwark/bootstrap.dat && rm $BOOTSTRAPARCHIVE

# Create bulwark.conf
touch $USERHOME/.bulwark/bulwark.conf
cat > $USERHOME/.bulwark/bulwark.conf << EOL
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
chmod 0600 $USERHOME/.bulwark/bulwark.conf
chown -R $USER:$USER $USERHOME/.bulwark

sleep 5

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
systemctl enable bulwarkd
echo "Starting bulwarkd..."
systemctl start bulwarkd

until [ -n "$(bulwark-cli getconnectioncount 2>/dev/null)"  ]; do
  sleep 1
done

if ! systemctl status bulwarkd | grep -q "active (running)"; then
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
  if systemctl is-active --quiet bulwarkd; then
  	systemctl start bulwarkd
fi
echo "Setting Up Staking Address.."

#Simple check to make sure the bulwarkd sync process is finished, so it isn't interrupted and forced to start over later.'
echo "Checking Bulwarkd status. The script will begin setting up staking once bulwarkd has finished syncing. Please allow this process to finish."
until su -c "bulwark-cli mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null" $USER; do
  echo -ne "Current block: "`su -c "bulwark-cli getinfo" $USER | grep blocks | awk '{print $3}' | cut -d ',' -f 1`'\r'
  sleep 1
done

#Ensure the .conf exists
touch ~/.bulwark/bulwark.conf

#If the line does not already exist, adds a line to bulwark.conf to instruct the wallet to stake

sed 's/staking=0/staking=1/' <~/.bulwark/bulwark.conf

if grep -Fxq "staking=1" ~/.bulwark/bulwark.conf; then
  	echo "Staking Already Active"
  else
  	echo "staking=1" >> ~/.bulwark/bulwark.conf
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
    sleep 0.5
done

#Open up bulwarkd again
systemctl start bulwarkd

#Unlocks the wallet for a long time period
bulwark-cli walletpassphrase $ENCRYPTIONKEY 9999999999 true

#Make decrypt script
cd ~/.bulwark
sudo wget https://raw.githubusercontent.com/KaneoHunter/shn/master/decrypt.sh
cp ~/.bulwark/decrypt.sh /usr/bin/local/bin/decrypt.sh
chown $USER:$USER /usr/local/bin/decrypt.sh
chmod 700 /usr/local/bin/decrypt.sh
rm -Rf ~/.bulwark/decrypt.sh


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
the included script by running "decrypt.sh" to unlock your
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

cat /dev/null > ~/.bash_history && history -c

clear

echo "Staking wallet operational."
