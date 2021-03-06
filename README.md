# Bulwark-Staking-Install

## Before you start

This script will try to create a safe environment for remote staking by hardening the remote server you stake on and force you to choose secure passwords for the user account accessing the server.

In total, you will set up three different passwords:

1.) An account password for the user you log in with  
2.) A SSH Key password for the key you authenticate with  
3.) A wallet password for your Bulwark staking wallet

Please make sure that all three follow [common guidelines](https://en.wikipedia.org/wiki/Password_strength#Common_guidelines) for secure passwords. **A staking server holds the actual coins you stake, and if it gets compromised, your funds can be stolen.**

During the installation, you will be asked to paste your SSH public key. If you are unfamiliar with SSH and key authentication, please read about the [protocol](https://www.ssh.com/ssh/protocol/) and [keys](https://www.ssh.com/ssh/key/) before you continue. The shortest explanation is this: You can hand your public key to anyone, and your private key to **NO ONE**. If you need help with creating an SSH key pair, you can follow our TODO: Guide.

## Overview

The installation will assumes a freshly installed Ubuntu 16.04 VPS. It will install dependencies and needed software for the installation, set up a user account that you can use to log into the server (logging in as root will be deactivated for security reasons), apply various patches to make the server more secure, then reboot it.

After the reboot, you can log in with the new account and activate staking.

## Installation

To get started, run the below script:

```bash
bash <( curl https://raw.githubusercontent.com/KaneoHunter/Bulwark-Staking-Install/master/setup.sh )
```

## Useful Commands

- Start the wallet - `systemctl start bulwarkd`
- Stop the wallet - `systemctl stop bulwarkd`
- Restart the wallet - `systemctl restart bulwarkd`
- Upload a debug log for devs/mods to look at (copy/paste us the output it gives!) - `curl --upload-file ~/.bulwark/debug.log https://transfer.sh/debug.log`
- Unlock your wallet for staking - `bulwark-decrypt`
- Find out if staking is working - `bulwark-cli getstakingstatus`
- See your current balance - `bulwark-cli getbalance`
- Find out information about your wallet - `bulwark-cli getinfo`
- Change the split-threshold for your staking transactions (default 2000) - `setstakesplitthreshold <# to split at>`

## Refreshing the wallet

Most issues with the wallet can be resolved by running the below:

`bash <( curl https://raw.githubusercontent.com/KaneoHunter/Bulwark-Staking-Install/master/refresh.sh )`

This is like a "factory reset" button.

## Updating the wallet

To update your wallet to the latest version of Bulwark, please run the below:

`bash <( curl https://raw.githubusercontent.com/KaneoHunter/Bulwark-Staking-Install/master/update.sh )`

## Troubleshooting

To make sure your wallet is staking, the 1st step is to use the following command:

```bash
bulwark-cli getstakingstatus`
```

This should hopefully look like this:

```text
{
    "validtime" : true,
    "haveconnections" : true,
    "walletunlocked" : true,
    "mintablecoins" : true,
    "enoughcoins" : true,
    "mnsync" : true,
    "staking status" : true
}
```

But let's go through how to fix each line.

### "Validtime"

This should always be true, this just shows that the POS period is active for the coin.

### "Haveconnections"

This makes sure you have valid peers, if this is showing as false I'd recommend the following command:

```bash
rm -Rf ~/.bulwark/peers.dat
```

and then running:

```bash
systemctl restart bulwarkd
```

### "Walletunlocked"

This means your wallet isn't unlocked, just run the below:

```bash
bulwark-cli walletpassphrase '<YOUR PASSWORD>' 99999999 true
```

This will unlock your wallet for staking only for a long time period.

### "Mintablecoins"

This is asking if your transaction is old enough to be staked. It takes 60 minutes for a transaction to be able to be staked. Just wait and this should correct to true.

### "Enoughcoins"

This is making sure you have more than 1 BWK in the wallet. If this is appearing false there are a wide number of potential problems. It's best to come ask us in Discord or Telegram linked on our [website](https://bulwarkcrypto.com/) if you have issues with this.

### "Mnsync"

This just makes sure your wallet is fully synced, if you appear to be fully synced I'd recomment typing:

```bash
bulwark-cli mnsync reset
```

and then closing the wallet with

```bash
systemctl stop bulwarkd
```

After this, wait a minute, then open it again with:

```bash
systemctl start bulwarkd
```

then wait 10 minutes more, before unlocking the wallet with the command:

```bash
bulwark-cli walletpassphrase '<YOUR PASSWORD>' 99999999 true
```

### Staking status

Staking status should be true, when staking=1 in your bulwark.conf, and when all other options are also true.

If you find yourself in a situation where this is false while all other indicators are true, type the below:

```bash
cat ~/.bulwark/bulwark.conf
```

and confirm the output from this command includes "staking=1".

If it does, follow the below steps:

```bash
systemctl stop bulwarkd
```

After this, wait a minute, then open it again with:

```bash
systemctl start bulwarkd
```

then wait 10 minutes more, before unlocking the wallet with the command:

```bash
bulwark-decrypt
```

Then, after a few more minutes of the network accepting your stakes, you should find everything to be true when you run

```bash
bulwark-cli getstakingstatus
```
