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

# Set the correct download path

VPSTARBALLURL=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep linux64 | cut -d '"' -f 4)
VPSTARBALLNAME=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep linux64 | cut -d '"' -f 4 | cut -d "/" -f 9)
SHNTARBALLURL=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep ARM | cut -d '"' -f 4)
SHNTARBALLNAME=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep ARM | cut -d '"' -f 4 | cut -d "/" -f 9)
BWKVERSION=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep browser_download_url | grep ARM | cut -d '"' -f 4 | cut -d "/" -f 8)
BOOTSTRAPURL=$(curl -s https://api.github.com/repos/bulwark-crypto/bulwark/releases/latest | grep bootstrap.dat.xz | grep browser_download_url | cut -d '"' -f 4)
BOOTSTRAPARCHIVE="bootstrap.dat.xz"

clear
cat << EOL
--------------------------------- DISCLAIMER ---------------------------------

This script is configured to install staking functionality with the utmost 
security and safety for your funds. Please ensure that the passwords you 
choose are a minimum of 16 characters with upper and lower case as well as 
numbers and symbols to help protect against brute force attacks.

Performing any acts not expressly provided by the script will render your 
staking wallet incapable of the Bulwark team being able to provide tech 
support. Additionally, maintenance and coin safety are the sole 
responsibility of the user.

If you do not expressly follow the script and the associated instructions, 
there is a very real chance your coins will be rendered inaccessible. 
Bulwark takes no responsibility for any coins that are lost or stolen.

EOL
read -rp "Press Ctrl-C to abort or any other key to continue. " -n1 -s

clear

# Install basic tools
echo "Preparing installation..."
sudo apt-get install git dnsutils systemd libpam-cracklib -y > /dev/null 2>&1

# Check for systemd
sudo systemctl --version >/dev/null 2>&1 || { echo "systemd is required. Are you using Ubuntu 16.04?"  >&2; exit 1; }

# Create a bulwark user
sudo adduser bulwark --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password > /dev/null

# Set cracklib to require secure passwords and force even root to use them
sudo sed -i '/pam_cracklib.so/ s/retry=3 minlen=8 difok=3/retry=10 minlen=8 dcredit=0 ucredit=0 lcredit=0 ocredit=0 difok=3 reject_username enforce_for_root/g' /etc/pam.d/common-password

clear

# Ask for a password, confirm it, then set the permissions for user bulwark
echo "Please enter a password for the bulwark user on your system."
echo "This user will be a sudoer - please make sure you understand the implications of this."
echo "See https://en.wikipedia.org/wiki/Sudo for more information."
echo ""
echo "USE A STRONG PASSWORD AND KEEP IT IN A SAFE PLACE."
echo -e "IF YOUR ACCOUNT GETS COMPROMISED, YOUR FUNDS CAN BE STOLEN!\\n"
sleep 2
until sudo passwd bulwark; do sudo passwd bulwark; done

# Now that bulwark has a password, the account can be a sudoer
sudo usermod -aG sudo bulwark

clear 

echo "You will now add your public SSH key to the server for authentication."
echo "If you do not have one, please follow the instructions in the README."

# Read public key from user.
echo -e "Please paste your public SSH key and press Enter: \\n"
read -er PUBKEY

# Check public key is correct
until echo "$PUBKEY" | ssh-keygen -lf /dev/stdin  &>/dev/null; do 
    echo "Incorrect key."
    echo -e "Please paste your public SSH key and press Enter: \\n"
    read -er PUBKEY && echo ""
done

# Write the public key

sudo mkdir /home/bulwark/.ssh
echo "$PUBKEY" | sudo tee -a /home/bulwark/.ssh/authorized_keys &> /dev/null
sudo chown -R bulwark:bulwark /home/bulwark/.ssh

# Generate random passwords
RPCUSER=$(dd if=/dev/urandom bs=3 count=512 status=none | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)
RPCPASSWORD=$(dd if=/dev/urandom bs=3 count=512 status=none | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

# update packages and upgrade Ubuntu
echo "Updating repository lists..."
sudo apt-get -qq update
echo "Installing upgrades..."
sudo apt-get -qq upgrade
echo "Autoremoving unneeded dependencies..."
sudo apt-get -qq autoremove
echo "Installing dependencies..."
sudo apt-get -qq install wget htop xz-utils build-essential libtool autoconf automake software-properties-common
echo "Adding repositories..."
sudo add-apt-repository -y ppa:bitcoin/bitcoin
echo "Updating added repository lists..."
sudo apt update
echo "Installing tools..."
sudo apt-get -qq install protobuf-compiler git pkg-config aptitude

# Install Fail2Ban
echo "Installing Fail2Ban..."
sudo aptitude -y -q install fail2ban
# Reduce Fail2Ban memory usage - http://hacksnsnacks.com/snippets/reduce-fail2ban-memory-usage/
echo "ulimit -s 256" | sudo tee -a /etc/default/fail2ban &> /dev/null
sudo service fail2ban restart


if ! grep -q "ARMv7" /proc/cpuinfo; then
  # Install UFW
  echo "Installing UFW..."
  sudo apt-get -qq install ufw
  echo "Configuring firewall..."
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow ssh
  sudo ufw allow 52543/tcp
  yes | sudo ufw enable
fi

echo "Downloading binaries..."
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

echo "Installing binaries..."
sudo mv "./bulwark-$BWKVERSION/bulwarkd" /usr/local/bin
sudo mv "./bulwark-$BWKVERSION/bulwark-cli" /usr/local/bin
sudo mv "./bulwark-$BWKVERSION/bulwark-tx" /usr/local/bin
rm -rf "bulwark-$BWKVERSION"

# Create .bulwark directory
sudo mkdir "/home/bulwark/.bulwark"

# Install bootstrap file
echo "Installing bootstrap file..."
sudo wget "$BOOTSTRAPURL" && sudo xz -d "$BOOTSTRAPARCHIVE" && sudo mv "bootstrap.dat" "/home/bulwark/.bulwark/"
echo "Creating configuration files..."

# Create bulwark.conf
sudo tee -a "/home/bulwark/.bulwark/bulwark.conf" &> /dev/null << EOL
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
sudo chmod 0600 "/home/bulwark/.bulwark/bulwark.conf"
sudo chown -R bulwark:bulwark "/home/bulwark/.bulwark"

sudo tee -a /etc/systemd/system/bulwarkd.service &> /dev/null << EOL
[Unit]
Description=Bulwarks's distributed currency daemon
After=network.target
[Service]
Type=forking
User=bulwark
WorkingDirectory=/home/bulwark
ExecStart=/usr/local/bin/bulwarkd -conf=/home/bulwark/.bulwark/bulwark.conf -datadir=/home/bulwark/.bulwark
ExecStop=/usr/local/bin/bulwark-cli -conf=/home/bulwark/.bulwark/bulwark.conf -datadir=/home/bulwark/.bulwark stop
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

until sudo su -c "$(bulwark-cli getconnectioncount 2>/dev/null)" bulwark; do
  sleep 1
done

if ! sudo systemctl status bulwarkd | grep -q "active (running)"; then
  echo "ERROR: Failed to start bulwarkd. Please contact support."
  exit
fi

echo "Waiting for wallet to load..."
until sudo su -c "bulwark-cli getinfo 2>/dev/null | grep -q 'version'" bulwark; do
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
until sudo su -c "bulwark-cli mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null" bulwark; do
  echo -ne "Current block: ""$(sudo su -c "bulwark-cli getinfo" bulwark | grep blocks | awk '{print $3}' | cut -d ',' -f 1)"'\r'
  sleep 1
done

# Ensure the .conf exists
sudo touch "/home/bulwark/.bulwark/bulwark.conf"

# If the line does not already exist, adds a line to bulwark.conf to instruct the wallet to stake

sudo sed -i 's/staking=0/staking=1/' "/home/bulwark/.bulwark/bulwark.conf"

if sudo grep -Fxq "staking=1" "/home/bulwark/.bulwark/bulwark.conf"; then
    echo "Staking Already Active"
  else
    echo "staking=1" | sudo tee -a "/home/bulwark/.bulwark/bulwark.conf"
fi

# Generate new address and assign it a variable
STAKINGADDRESS=$(sudo su -c "bulwark-cli getnewaddress" bulwark)

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
BIP38=$(sudo su -c "bulwark-cli bip38encrypt $STAKINGADDRESS '$ENCRYPTIONKEY'" bulwark)
echo "Address successfully encrypted! Please wait for encryption to finish..."

# Encrypt the wallet with the same password
sudo su -c "bulwark-cli encryptwallet '$ENCRYPTIONKEY'" bulwark && echo "Wallet successfully encrypted!"

# Wait for bulwarkd to close down after wallet encryption
echo "Waiting for bulwarkd to restart..."
until  ! sudo systemctl is-active --quiet bulwarkd; do sleep 1; done

# Open up bulwarkd again
sudo systemctl start bulwarkd

# Wait for bulwarkd to open up again
until sudo su -c "bulwark-cli getinfo" bulwark; do sleep 1; done

# Unlock the wallet for a long time period
sudo su -c "bulwark-cli walletpassphrase '$ENCRYPTIONKEY' 9999999999 true" bulwark

# Create decrypt.sh and service

#Check if it already exists, remove if so.
if [  -e /usr/local/bin/bulwark-decrypt ]; then sudo rm /usr/local/bin/bulwark-decrypt; fi

#create decrypt.sh
sudo tee &> /dev/null /usr/local/bin/bulwark-decrypt << EOL
#!/bin/bash

# Stop writing to history
set +o history

# Confirm wallet is synced
until sudo su -c "bulwark-cli mnsync status 2>/dev/null | grep '\"IsBlockchainSynced\" : true' > /dev/null" bulwark; do
  echo -ne "Current block: "$(sudo su -c "bulwark-cli getinfo | grep blocks | awk '{print $3}' | cut -d ',' -f 1)'\\r'") bulwark
  sleep 1
done

# Unlock wallet
until sudo su -c "bulwark-cli getstakingstatus | grep walletunlocked | grep true" bulwark; do

  #ask for password and attempt it
  read -e -s -p "Please enter a password to decrypt your staking wallet. Your password will not show as you type : " ENCRYPTIONKEY && echo "\\n"
  sudo su -c "bulwark-cli walletpassphrase '$ENCRYPTIONKEY' 99999999 true" bulwark
done

# Tell user all was successful
echo "Wallet successfully unlocked!"
echo " "
sudo su -c "bulwark-cli getstakingstatus" bulwark
sudo su bulwark

# Restart history
set -o history
EOL

sudo chmod a+x /usr/local/bin/bulwark-decrypt
sudo chown -R bulwark:bulwark "/home/bulwark/.bulwark/"

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

echo "Thank you for installing your Bulwark staking wallet!"

unset CONFIRMATION ENCRYPTIONKEYCONF ENCRYPTIONKEY BIP38 STAKINGADDRESS

set -o history
clear

echo "Staking wallet operational. Will now harden your system and reboot."
sleep 2

# Harden fstab
echo "Hardening fstab..."
sudo sed -i '/tmpfs/ s/defaults\s/defaults,nodev,nosuid,noexec /g' /etc/fstab

# Harden networking layer
echo "Adding networking rules..."
sudo tee -a /etc/sysctl.conf &> /dev/null << EOL

# IP Spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0 
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Block SYN attacks
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0 
net.ipv6.conf.default.accept_redirects = 0

# Ignore Directed pings
net.ipv4.icmp_echo_ignore_all = 1
EOL

# Harden sshd_config
echo "Hardening sshd_config..."
sudo tee /etc/ssh/sshd_config &> /dev/null << EOL
# Bulwark-Staking-Install generated configuration file
# See the sshd_config(5) manpage for details

# What ports, IPs and protocols we listen for
Port 22

# Use these options to restrict which interfaces/protocols sshd will bind to
#ListenAddress ::
ListenAddress 0.0.0.0
Protocol 2

# HostKeys for protocol version 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Change default ciphers and algorithms
KexAlgorithms curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com

#Privilege Separation is turned on for security
UsePrivilegeSeparation yes

# Lifetime and size of ephemeral version 1 server key
KeyRegenerationInterval 3600
ServerKeyBits 1024

# Logging
SyslogFacility AUTH
LogLevel INFO

# Authentication:
LoginGraceTime 120
PermitRootLogin no
StrictModes yes

RSAAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile	%h/.ssh/authorized_keys

# Don't read the user's ~/.rhosts and ~/.shosts files
IgnoreRhosts yes
# For this to work you will also need host keys in /etc/ssh_known_hosts
RhostsRSAAuthentication no
# similar for protocol version 2
HostbasedAuthentication no
# Uncomment if you don't trust ~/.ssh/known_hosts for RhostsRSAAuthentication
#IgnoreUserKnownHosts yes

# To enable empty passwords, change to yes (NOT RECOMMENDED)
PermitEmptyPasswords no

# Change to yes to enable challenge-response passwords (beware issues with
# some PAM modules and threads)
ChallengeResponseAuthentication no

# Change to no to disable tunnelled clear text passwords
PasswordAuthentication no

# Kerberos options
#KerberosAuthentication no
#KerberosGetAFSToken no
#KerberosOrLocalPasswd yes
#KerberosTicketCleanup yes

# GSSAPI options
#GSSAPIAuthentication no
#GSSAPICleanupCredentials yes

X11Forwarding no 
X11DisplayOffset 10
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
#UseLogin no

#MaxStartups 10:30:60
#Banner /etc/issue.net

# Allow client to pass locale environment variables
AcceptEnv LANG LC_*

Subsystem sftp /usr/lib/openssh/sftp-server

# Disconnect idle sessions
ClientAliveInterval 300
ClientAliveCountMax 2

# Set this to 'yes' to enable PAM authentication, account processing,
# and session processing. If this is enabled, PAM authentication will
# be allowed through the ChallengeResponseAuthentication and
# PasswordAuthentication.  Depending on your PAM configuration,
# PAM authentication via ChallengeResponseAuthentication may bypass
# the setting of "PermitRootLogin without-password".
# If you just want the PAM account and session checks to run without
# PAM authentication, then enable this but set PasswordAuthentication
# and ChallengeResponseAuthentication to 'no'.
UsePAM no
EOL

# Prevent spoofing
echo "Preventing spoofing..."
sudo tee /etc/host.conf &> /dev/null << EOL
# The "order" line is only used by old versions of the C library.
order bind,hosts
nospoof on
EOL

# Add unattended upgrades
echo "Adding unattended upgrades..."
sudo apt install -y unattended-upgrades &> /dev/null

clear
echo "Hardening complete."
sleep 2
clear
cat << EOL
PLEASE NOTE:

After the system reboots, you can no longer log in with the root user. You will need to
log in with the bulwark user and the password you set earlier.

The first time you try to log in after the reboot, you will get the following error:

@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

Don't be alarmed, this is not because you were attacked, but because we set a different 
host key to be used for SSH. Please refer to the README on how to fix this.

EOL
sleep 5
echo "Press Enter to reboot."
read -r 
sudo shutdown -r now
