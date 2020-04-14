# nrgCheck
Check if your VPS is ok

Prerequisites:
- jq : sudo apt-get install jq
- jo : sudo apt-get install jo
- ssmtp : sudo apt-get instal ssmtp (look on google how to install & configure)

Install:
- Copy the check.sh into you nrg home directory (usually /home/nrgstaker)
- Add it in nrgstaker crontab for example each 20min: */20 * * * * /home/nrgstaker/check.sh
