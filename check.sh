#!/bin/bash
#set -x

# energi3 user
ENERGI_USR=nrgstaker
ENERGI_CMD=~/energi3/bin/energi3
ENERGI_PRM=~/check_param.json
ENERGI_TMP=~/check.tmp
ENERGI_JSN=~/check.json

# Email
EMAIL_CMD=/usr/sbin/ssmtp
EMAIL_DST=your.email@gmail.com
EMAIL_TMP=~/check_message.txt

# Create parameter file if !exist (json file)
# if the file exist, modify it directly(0 = option disabled)
# isMasterNode: perform MasterNode checks
# isStaking : perform Staking checks
# isSynced : perfom Synchronisation tests (beta)
# delayBlocks : number of delay blocks allowed, can be both ways (default :3)
if [ ! -f "$ENERGI_PRM" ] ; then
    cat << !EOF > $ENERGI_PRM
{
   "isMasterNode": 0,
   "isStaking": 1,
   "isSynced": 1,
   "delayBlocks": 3
}
!EOF
fi

# Read parameters
IS_MN=$(jq -r '.isMasterNode' $ENERGI_PRM)
IS_ST=$(jq -r '.isStaking' $ENERGI_PRM)
IS_SC=$(jq -r '.isSynced' $ENERGI_PRM)
SC_DELAYBLOCKS=$(jq -r '.delayBlocks' $ENERGI_PRM)

# Save last wallet balance value
WALLET_LAST_BAL=$(jq -r '.balance' $ENERGI_JSN)
WALLET_LAST_DLT=$(jq -r '.balance_delta' $ENERGI_JSN)
WALLET_LAST_CHG=$(jq -r '.balance_changed' $ENERGI_JSN)

# Get Masternode Infos
if [ $IS_MN = 1 ] ; then
        $ENERGI_CMD attach --exec "masternode.masternodeInfo(personal.listAccounts[0])" >> $ENERGI_TMP
        MN_COLLATERAL=$($ENERGI_CMD attach --exec "web3.fromWei(masternode.masternodeInfo(personal.listAccounts[0]).collateral, 'ether')" | sed 's/\"//g')
        echo "  nrgCollateral: $MN_COLLATERAL" >> $ENERGI_TMP

        # MN_REWARD=colletaral / 1000 x 0.914
        MN_REWARD=$(echo "scale=2;$MN_COLLATERAL / 1000 * 0.914" | bc -l)
        echo "  mnReward: $MN_REWARD" >> $ENERGI_TMP
fi

# Get Staking infos
if [ $IS_ST = 1 ] ; then
        $ENERGI_CMD attach --exec "miner.stakingStatus()" >> $ENERGI_TMP
fi

# Get Last generated block
if [ $IS_SC = 1 ] ; then
        LAST_BLOCK_HEX=$(curl -s "https://explorer.energi.network/api?module=block&action=eth_block_number" | jq -r '.result' | tr [a-z] [A-Z]| cut -dX -f2)
        LAST_BLOCK_DEC=$(echo "obase=10; ibase=16;$LAST_BLOCK_HEX"| bc)
        echo "  eth_block_number: $LAST_BLOCK_DEC" >> $ENERGI_TMP
fi

# Get NRG Balance
ENERGI_BAL=$($ENERGI_CMD attach --exec "web3.fromWei(eth.getBalance(personal.listAccounts[0]), 'ether')")
echo "  balance: $ENERGI_BAL" >> $ENERGI_TMP

# Update Wallet value changed/delta if needed
if [ "x$ENERGI_BAL" != "x$WALLET_LAST_BAL" ]
then
        echo "  balance_changed: $(date +%s)" >> $ENERGI_TMP
        echo "  balance_delta: $(echo "$ENERGI_BAL - $WALLET_LAST_BAL" | bc)" >> $ENERGI_TMP
else
        echo "  balance_changed: $WALLET_LAST_CHG" >> $ENERGI_TMP
        echo "  balance_delta: $WALLET_LAST_DLT" >> $ENERGI_TMP
fi

# Temp file to JSON ( for future web integration)
while read ligne
do
        param=$(echo $ligne| awk -F': |,' '{print $1}')
        value=$(echo $ligne| awk -F': |,' '{print $2}')
        JO_CMD="$JO_CMD $param=$value"
done <<<$(cat $ENERGI_TMP | egrep "mnReward:|nrgCollateral:|isActive:|isAlive:|miner:|staking:|balance:|balance_changed:|balance_delta:|height:|totalWeight:|announcedBlock:|swFeatures:|swVersion:|eth_block_number:" | egrep -v "modules")
rm $ENERGI_TMP
jo -p $JO_CMD > $ENERGI_JSN


## Check list : ##

# check 1 : Masternode
MN_ALIVE=$(jq -r '.isAlive' $ENERGI_JSN)
MN_ACTIVE=$(jq -r '.isActive' $ENERGI_JSN)
if [ "x$MN_ALIVE" != "xtrue" -o "x$MN_ACTIVE" != "xtrue" ]
then
        MN_STATUS="KO (alive:$MN_ALIVE, active:$MN_ACTIVE)"
else
        MN_STATUS="OK"
fi

# Check 2 : Staking
ST_MINING=$(jq -r '.miner' $ENERGI_JSN)
ST_STAKING=$(jq -r '.staking' $ENERGI_JSN)
if [ "x$ST_MINING" != "xtrue" -o "x$ST_STAKING" != "xtrue" ]
then
        ST_STATUS="KO (mining:$ST_MINING, staking: $ST_STAKING)"
else
        ST_STATUS="OK"
fi

# Check 3 : Core Node Synced
SC_LAST=$(jq -r '.eth_block_number' $ENERGI_JSN)
SC_LOCAL=$(jq -r '.height' $ENERGI_JSN)
SC_DELTA=$(expr $SC_LAST - $SC_LOCAL)
if [ ${SC_DELTA#-} -gt $SC_DELAYBLOCKS ]
then
        SC_STATUS="KO (last_block_generated:$SC_LAST, local_block:$SC_LOCAL)"
else
        SC_STATUS="OK"
fi

# New Balance to check with last
WALLET_CURR_BAL=$(jq -r '.balance' $ENERGI_JSN)




## EMAIL IF CHECK NOK ##

# Masternode + Staking
if [ $IS_MN = 1 -a "x$MN_STATUS" != "xOK" ] || [ $IS_ST = 1 -a "x$ST_STATUS" != "xOK" ] || [ $IS_SC = 1 -a "x$SC_STATUS" != "xOK" ]
then
        echo "Subject: -ERROR- Energi MN Problem !" >> $EMAIL_TMP
        echo "" >> $EMAIL_TMP
        if [ $IS_MN = 1 ] ; then
                echo "MasterNode : $MN_STATUS" >> $EMAIL_TMP
        fi

        if [ $IS_ST = 1 ] ; then
                echo "StakingNRG : $ST_STATUS" >> $EMAIL_TMP
        fi

        if [ $IS_SC = 1 ] ; then
                echo "Synced : $SC_STATUS" >> $EMAIL_TMP
        fi

        # Send Email
        $EMAIL_CMD $EMAIL_DST < $EMAIL_TMP
        rm $EMAIL_TMP

        exit 1
fi

# Wallet changed

if [ "x$ENERGI_BAL" != "x$WALLET_LAST_BAL" ]
then

        # Time since last wallet balance change
        NB_SEC=$(echo "scale=2;($(date +%s) - $WALLET_LAST_CHG)" | bc -l)
        TXT_CHANGED_SINCE=$(echo $NB_SEC | awk '{printf "%02dj %02dh %02dm %02ds\n",int($1/3600/24), int($1/3600%24), int($1/60%60), $1%60}')

        WALLET_DELTA=$(jq -r '.balance_delta' $ENERGI_JSN)
        MN_REWARD=$(jq -r '.mnReward' $ENERGI_JSN)

        if [ "$WALLET_DELTA" = "$MN_REWARD" ]
        then
                echo "Subject: [Energi] New MN reward!" >> $EMAIL_TMP
        elif [ "$WALLET_DELTA" = "2.28" ]
        then
                echo "Subject: [Energi] New Staking reward!" >> $EMAIL_TMP
        else
                echo "Subject: [Energi] Wallet change" >> $EMAIL_TMP
        fi

        echo "" >> $EMAIL_TMP
        echo "Last changed : $TXT_CHANGED_SINCE" >> $EMAIL_TMP
        echo "Delta : $WALLET_DELTA NRG" >> $EMAIL_TMP

        # Send Email
        $EMAIL_CMD $EMAIL_DST < $EMAIL_TMP
        rm $EMAIL_TMP

fi

exit 0
