#!/bin/bash

#turn off history logging
set +o history

# Check if we have enough memory
if [[ $(free -m | awk '/^Mem:/{print $2}') -lt 850 ]]; then
  echo "This installation requires at least 1GB of RAM.";
  exit 1
fi

# Check if we have enough disk space
if [[ $(df -k --output=avail / | tail -n1) -lt 10485760 ]]; then
  echo "This installation requires at least 10GB of free disk space.";
  exit 1
fi

# Install curl before we do anything else
echo "Installing curl..."
sudo apt-get install -y curl

# Set these to change the version of Bulwark to install

VPSTARBALLURL=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep linux64 | cut -d '"' -f 4)
VPSTARBALLNAME=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep linux64 | cut -d '"' -f 4 | cut -d "/" -f 9)
SHNTARBALLURL=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep ARM | cut -d '"' -f 4)
SHNTARBALLNAME=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep ARM | cut -d '"' -f 4 | cut -d "/" -f 9)
BWKVERSION=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep ARM | cut -d '"' -f 4 | cut -d "/" -f 8)
BOOTSTRAPURL=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep bootstrap.dat.xz | grep browser_download_url | cut -d '"' -f 4)
BOOTSTRAPARCHIVE="bootstrap.dat.xz"

clear
echo "This script will install a Bulwark staking wallet."
read -rp "Press Ctrl-C to abort or any other key to continue. " -n1 -s

clear

# Install basic tools
echo "Preparing installation..."
sudo apt-get install git dnsutils systemd -y > /dev/null 2>&1

# Check for systemd
sudo systemctl --version >/dev/null 2>&1 || { echo "systemd is required. Are you using Ubuntu 16.04?"  >&2; exit 1; }

# Create a bulwark user
adduser bulwark --gecos "First Last,RoomNumber,WorkPhone,HomePhone" > /dev/null

# Set the user
USER=bulwark
USERHOME=$(eval echo "~bulwark")

# Generate random passwords
RPCUSER=$(dd if=/dev/urandom bs=3 count=512 status=none | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
RPCPASSWORD=$(dd if=/dev/urandom bs=3 count=512 status=none | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

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

if grep -q "ARMv7" /proc/cpuinfo; then
  # Install Bulwark daemon for ARMv7 systems
  wget "$SHNTARBALLURL"
  tar -xzvf "$SHNTARBALLNAME" && mv bin "bulwark-$BWKVERSION"
  rm "$SHNTARBALLNAME"
else
  # Install Bulwark daemon for x86 systems
  wget "$VPSTARBALLURL"
  tar -xzvf "$VPSTARBALLNAME" && mv bin "bulwark-$BWKVERSION"
  rm "$VPSTARBALLNAME"
fi

sudo mv "./bulwark-$BWKVERSION/bulwarkd" /usr/local/bin
sudo mv "./bulwark-$BWKVERSION/bulwark-cli" /usr/local/bin
sudo mv "./bulwark-$BWKVERSION/bulwark-tx" /usr/local/bin
rm -rf "bulwark-$BWKVERSION"

# Create .bulwark directory
mkdir "$USERHOME/.bulwark"

# Install bootstrap file
echo "Installing bootstrap file..."
wget "$BOOTSTRAPURL" && xz -cd "$BOOTSTRAPARCHIVE" > "$USERHOME/.bulwark/bootstrap.dat" && rm "$BOOTSTRAPARCHIVE"

echo "Creating configuration files..."

# Create bulwark.conf
sudo tee -a "$USERHOME/.bulwark/bulwark.conf" << EOL
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
sudo chmod 0600 "$USERHOME/.bulwark/bulwark.conf"
sudo chown -R $USER:$USER "$USERHOME/.bulwark"

sudo tee -a /etc/systemd/system/bulwarkd.service << EOL
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
echo "Starting bulwarkd..."
sudo systemctl start bulwarkd

until sudo su -c "$(bulwark-cli getconnectioncount 2>/dev/null)" $USER; do
  sleep 1
done

if ! sudo systemctl status bulwarkd | grep -q "active (running)"; then
  echo "ERROR: Failed to start bulwarkd. Please contact support."
  exit
fi

echo "Waiting for wallet to load..."
until sudo su -c "bulwark-cli getinfo 2>/dev/null | grep -q 'version'" $USER; do
  sleep 1;
done

clear

echo "Your node has been set up, now setting up staking..."

sleep 5

# Ensure bulwarkd is active
  if sudo systemctl is-active --quiet bulwarkd; then
  	sudo systemctl start bulwarkd
fi
echo "Setting Up Staking Address.."

# Check to make sure the bulwarkd sync process is finished, so it isn't interrupted and forced to start over later.'
echo "The script will begin set up staking once bulwarkd has finished syncing. Please allow this process to finish."
until sudo su -c "bulwark-cli mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null" $USER; do
  echo -ne "Current block: ""$(sudo su -c "bulwark-cli getinfo" $USER | grep blocks | awk '{print $3}' | cut -d ',' -f 1)"'\r'
  sleep 1
done

# Ensure the .conf exists
sudo touch "$USERHOME/.bulwark/bulwark.conf"

# If the line does not already exist, adds a line to bulwark.conf to instruct the wallet to stake

sudo sed -i 's/staking=0/staking=1/' "$USERHOME/.bulwark/bulwark.conf"

if grep -Fxq "staking=1" "$USERHOME/.bulwark/bulwark.conf"; then
  	echo "Staking Already Active"
  else
  	echo "staking=1" | sudo tee -a "$USERHOME/.bulwark/bulwark.conf"
fi

# Generate new address and assign it a variable
STAKINGADDRESS=$(sudo su -c "bulwark-cli getnewaddress" $USER)

# Ask for a password and apply it to a variable and confirm it.
ENCRYPTIONKEY=1
ENCRYPTIONKEYCONF=2
echo "Please enter a password to encrypt your new staking address/wallet with, you will not see what you type appear."
echo -e 'KEEP THIS SAFE, THIS CANNOT BE RECOVERED!\n'
until [ "$ENCRYPTIONKEY" = "$ENCRYPTIONKEYCONF" ]; do
	read -ersp "Please enter your password   : " ENCRYPTIONKEY && echo -e '\n'
	read -ersp "Please confirm your password : " ENCRYPTIONKEYCONF && echo -e '\n'
	if [ "$ENCRYPTIONKEY" != "$ENCRYPTIONKEYCONF" ]; then
		echo "Your passwords do not match, please try again."
	else
		echo "Password set."
	fi
done

# Encrypt the new address with the requested password
BIP38=$(sudo su -c "bulwark-cli bip38encrypt $STAKINGADDRESS '$ENCRYPTIONKEY'" $USER)
echo "Address successfully encrypted! Please wait for encryption to finish..."

# Encrypt the wallet with the same password
sudo su -c "bulwark-cli encryptwallet '$ENCRYPTIONKEY'" $USER && echo "Wallet successfully encrypted!"

# Wait for bulwarkd to close down after wallet encryption
echo "Waiting for bulwarkd to restart..."
until  ! sudo systemctl is-active --quiet bulwarkd; do sleep 1; done

# Open up bulwarkd again
sudo systemctl start bulwarkd

# Wait for bulwarkd to open up again
until sudo su -c "bulwark-cli getinfo" $USER; do sleep 1; done

# Unlock the wallet for a long time period
sudo su -c "bulwark-cli walletpassphrase '$ENCRYPTIONKEY' 9999999999 true" $USER

# Create decrypt.sh and service

#Check if it already exists, remove if so.
if [  -e /usr/local/bin/bulwark-decrypt ]; then sudo rm /usr/local/bin/bulwark-decrypt; fi

#create decrypt.sh
sudo tee /usr/local/bin/bulwark-decrypt << EOL
#!/bin/bash

# Stop writing to history
set +o history

# Confirm wallet is synced
until bulwark-cli --conf=/home/bulwark/.bulwark/bulwark.conf --datadir=/home/bulwark/.bulwark/ mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null; do
  echo -ne "Current block: \$(sudo bulwark-cli --conf=/home/bulwark/.bulwark/bulwark.conf --datadir=/home/bulwark/.bulwark/ getinfo | grep blocks | awk '{print \$3}' | cut -d ',' -f 1)'\\r')"
  sleep 1
done

# Unlock wallet
until bulwark-cli --conf=/home/bulwark/.bulwark/bulwark.conf --datadir=/home/bulwark/.bulwark/ getstakingstatus | grep walletunlocked | grep true; do

  #ask for password and attempt it
  read -e -s -p "Please enter a password to decrypt your staking wallet. Your password will not show as you type : " ENCRYPTIONKEY && echo "\\n"
  bulwark-cli --conf=/home/bulwark/.bulwark/bulwark.conf --datadir=/home/bulwark/.bulwark/ walletpassphrase "\$ENCRYPTIONKEY" 99999999 true
done

# Tell user all was successful
echo "Wallet successfully unlocked!"
echo " "
bulwark-cli --conf=/home/bulwark/.bulwark/bulwark.conf --datadir=/home/bulwark/.bulwark/ getstakingstatus

# Restart history
set -o history
EOL

sudo chmod a+x /usr/local/bin/bulwark-decrypt
sudo chown -R $USER:$USER "$USERHOME/.bulwark/"

# Create bulwark-cli alias for root
echo alias bulwark-cli="bulwark-cli --conf=/home/bulwark/.bulwark/bulwark.conf --datadir=/home/bulwark/.bulwark/" > ~/.bashrc
# shellcheck source=/dev/null
source ~/.bashrc

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
the included script by typing "bulwark-decrypt" to unlock your wallet securely.

After the installation script ends, we will wipe all history and have no
storage record of your password, encrypted key, or addresses.
Any funds you lose access to are your own responsibility and the Bulwark team
will be unable to assist with their recovery. We therefore suggesting saving a
physical copy of this information.

If you have any concerns, we encourage you to contact us via any of our
social media channels.

EOL

until [  "$CONFIRMATION" = "I have read the above and agree"  ]; do
    read -erp "Please confirm you have written down your password and encrypted key somewhere
    safe by typing \"I have read the above and agree\" : " CONFIRMATION
done

echo "Thank you for installing your Bulwark staking wallet, now finishing installation..."

unset CONFIRMATION ENCRYPTIONKEYCONF ENCRYPTIONKEY BIP38 STAKINGADDRESS

set -o history

clear

echo "Staking wallet operational. Do not forget to unlock your wallet!"

#logs user in to bulwark account from root
echo "Please set a password to log-in to your VPS with, your username will be $USER"
passwd $USER
sudo su $USER && cd ~
