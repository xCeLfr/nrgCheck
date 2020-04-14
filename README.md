# nrgCheck
Check if your VPS is ok

prerequisites:
jq : sudo apt-get instal jq
jo : sudo apt-get instal jo
ssmtp : sudo apt-get instal ssmtp (look on google how to install & configure)

install:
- Copy the check.sh into you nrg home directory (usually /home/nrgstaker)
- Add it in nrgstaker crontab
for example : (each 20min) 
*/20 * * * * /home/nrgstaker/check.sh


