# Bulwark-Staking-Install

Simple script to get staking on a VPS without a masternode!

To get started, run the below script:

```
bash <( curl https://raw.githubusercontent.com/KaneoHunter/Bulwark-Staking-Install/master/setup.sh )
```

If you need to see the message displayed at the end of the script after the script has finished, enter:
```
cat ~/.bulwark/StakingInfoReadMe.txt
```

It's recommended to write all outputs given to you down, and store them somewhere safe asap. Once stored in a safe place please enter the below command:

```
rm -Rf ~/.bulwark/StakingInfoReadMe.txt
```

This deletes the document containing your passwords and import keys, making sure your VPS is as safe as possible.

# Useful Commands

Start the wallet - `systemctl start bulwarkd`  
Stop the wallet - `systemctl stop bulwarkd`  
Restart the wallet - `systemctl restart bulwarkd`  
Upload a debug log for devs/mods to look at (copy/paste us the output it gives!) - `curl --upload-file ~/.bulwark/debug.log https://transfer.sh/debug.log`  
Unlock your wallet for staking - `bulwark-cli walletpassphrase '<YOUR PASSWORD>' 99999999 true`  
Find out if staking is working - `bulwark-cli getstakingstatus`  
See your current balance - `bulwark-cli getbalance`  
Find out information about your wallet - `bulwark-cli getinfo`  
Change the split-threshold for your staking transactions (default 2000) - `setstakesplitthreshold <# to split at>`  

# Refreshing the wallet

Most issues with the wallet can be resolved by running the below:

`bash <( curl https://raw.githubusercontent.com/bulwark-crypto/Bulwark-MN-Install/master/refresh_node.sh )`

This is like a "factory reset" button.

# Troubleshooting

To make sure your wallet is staking, the 1st step is to use the following command:

```
bulwark-cli getstakingstatus`
```

This should hopefully look like this:

```
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

## "Validtime"

This should always be true, this just shows that the POS period is active for the coin.

## "Haveconnections"

This makes sure you have valid peers, if this is showing as false I'd recommend the following command:

```
rm -Rf ~/.bulwark/peers.dat
```
and then running:
```
systemctl restart bulwarkd
```

## "Walletunlocked"

This means your wallet isn't unlocked, just run the below:

```
bulwark-cli walletpassphrase '<YOUR PASSWORD>' 99999999 true
```

This will unlock your wallet for staking only for a long time period. Unlocking for staking only means your funds are safe even if a malicious entity got access to your VPS.

## "Mintablecoins"

This is asking if your transaction is old enough to be staked. It takes 60 minutes for a transaction to be able to be staked. Just wait and this should correct to true.

## "Enoughcoins"

This is making sure you have more than 1 BWK in the wallet. If this is appearing false there are a wide number of potential problems. It's best to come ask us in Discord or Telegram linked on our website (https://bulwarkcrypto.com/) if you have issues with this.

## "Mnsync"

This just makes sure your wallet is fully synced, if you appear to be fully synced I'd recomment typing:

```
bulwark-cli mnsync reset
```
and then closing the wallet with
```
systemctl stop bulwarkd
```
After this, wait a minute, then open it again with:
```
systemctl start bulwarkd
```
then wait 10 minutes more, before unlocking the wallet with the command:
```
bulwark-cli walletpassphrase '<YOUR PASSWORD>' 99999999 true
```

## Staking status

Staking status should be true, when staking=1 in your bulwark.conf, and when all other options are also true.

If you find yourself in a situation where this is false while all other indicators are true, type the below:
```
cat ~/.bulwark/bulwark.conf
```
and confirm the output from this command includes "staking=1".

If it does, follow the below steps:

```
systemctl stop bulwarkd
```
After this, wait a minute, then open it again with:
```
systemctl start bulwarkd
```
then wait 10 minutes more, before unlocking the wallet with the command:
```
bulwark-cli walletpassphrase '<YOUR PASSWORD>' 99999999 true
```
Then, after a few more minutes of the network accepting your stakes, you should find everything to be true when you run
```
bulwark-cli getstakingstatus
```
again!
