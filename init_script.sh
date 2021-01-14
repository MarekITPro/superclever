#! /bin/bash
# check params :)
if [[ $# -ne 6 ]]; then
    echo "Illegal number of parameters, use: script.sh sql_sa_password database_name sas_key storage_acc_name storage_cont beats_pass"
    exit 2
fi

# wait for disk to come online (max 50 minutes)
counter=0
while [ ! -e /dev/sdc ]; do
    sleep 1m
    counter=$((counter + 1))
    if [ $counter -ge 50 ]; then
        exit
    fi
done

echo "partition data disk"
sudo parted /dev/disk/azure/scsi1/lun0 mklabel gpt
sudo parted -a opt /dev/disk/azure/scsi1/lun0 mkpart primary ext4 0% 100%

# wait for partition to show up before attempting format
sleep 1m

# allow kernel to catch up before checking for lun0-part1 (max 10 minutes - tbc for 20TB disk!)
counter=0
while [ ! -e /dev/disk/azure/scsi1/lun0-part1 ]; do
    sleep 1m
    counter=$((counter + 1))
    if [ $counter -ge 10 ]; then
        exit
    fi
done

echo "format disk"
sudo mkfs.xfs /dev/disk/azure/scsi1/lun0-part1

echo "mount as /datadrive"
sudo mkdir /datadrive
sudo mount /dev/disk/azure/scsi1/lun0-part1 /datadrive

echo "make folders"
sudo mkdir /datadrive/tools
sudo mkdir /datadrive/backup
sudo mkdir /datadrive/restore
sudo mkdir /datadrive/restore/data
sudo mkdir /datadrive/restore/log

echo "set RWX permissions on /datadrive and subfolders"
sudo chmod -R 777 /datadrive/

echo "install PowerShell"
# Update the list of packages
sudo apt-get update
# Install pre-requisite packages.
sudo apt-get install -y wget apt-transport-https software-properties-common
# Download the Microsoft repository GPG keys
wget -q https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb
# Register the Microsoft repository GPG keys
sudo dpkg -i packages-microsoft-prod.deb
# Update the list of products
sudo apt-get update
# Enable the "universe" repositories
sudo add-apt-repository universe
# Install PowerShell
sudo apt-get install -y powershell

sleep 1m

echo "setting variables needed later"
# Setting some vars from script params
SQL_SA_PASSWORD=$1
DATABASE_NAME=$2
echo $DATABASE_NAME
SAS_KEY=$3
STORAGE_ACC=$4
STORAGE_CONT=$5
BEATS_PASS=$6
export BEATS_PASS

echo "Setting local SQL SA pwd"
# Set local SA password for SQL instance
sudo systemctl stop mssql-server
sleep 1m
sudo MSSQL_SA_PASSWORD=$SQL_SA_PASSWORD /opt/mssql/bin/mssql-conf set-sa-password
# set default data and log dirs to BIG disk to avoid running restore with relocation switch
echo "Setting SQL data and log dirs"
sudo MSSQL_SA_PASSWORD=$SQL_SA_PASSWORD /opt/mssql/bin/mssql-conf set filelocation.defaultdatadir /datadrive/restore/data
sudo MSSQL_SA_PASSWORD=$SQL_SA_PASSWORD /opt/mssql/bin/mssql-conf set filelocation.defaultlogdir /datadrive/restore/log
sleep 1m
sudo systemctl start mssql-server

echo "Installing beat"
# enroll beat and tag it with output
/tmp/install_filebeat.sh fb-out-mssql

echo "Invoking PowerShell to download, restore and run dbcc checkdb"
/tmp/sqldbcheck.ps1 -SASTOKEN $SAS_KEY -dbName $DATABASE_NAME -azStorageAccName $STORAGE_ACC -azStorageContainer $STORAGE_CONT -sqlSAPass $SQL_SA_PASSWORD

echo "done, or is it? :)"
