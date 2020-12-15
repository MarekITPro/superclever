#! /bin/bash
# check params - must be two :)
if [[ $# -ne 2 ]]; then
    echo "Illegal number of parameters, use: restore_and_check_db.sh sql_sa_password database_name"
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

# wait for partition to show up before formatting - kernel to catch up (max 10 minutes - tbc for 20TB disk!)
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

echo "set RWX permissions on /datadrive and subs"
sudo chmod -R 777 /datadrive/

echo "download azcopy"
sudo wget -O /datadrive/tools/azcopy_v10.tar.gz https://aka.ms/downloadazcopy-v10-linux 

echo "extract azcopy"
sudo tar -xf /datadrive/tools/azcopy_v10.tar.gz --strip-components=1 -C /datadrive/tools
sudo chmod +x /datadrive/tools/azcopy

echo "install AzureCLI"
sudo curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# download the package to the VM 
wget -O /tmp/telegraf_1.8.0~rc1-1_amd64.deb https://dl.influxdata.com/telegraf/releases/telegraf_1.8.0~rc1-1_amd64.deb 

# install the package 
sudo dpkg -i /tmp/telegraf_1.8.0~rc1-1_amd64.deb

# generate the new Telegraf config file in the current directory 
telegraf --input-filter cpu:mem --output-filter azure_monitor config > /tmp/azm-telegraf.conf 

# replace the example config with the new generated config 
sudo cp /tmp/azm-telegraf.conf /etc/telegraf/telegraf.conf

# stop the telegraf agent on the VM 
sudo systemctl stop telegraf 
# start the telegraf agent on the VM to ensure it picks up the latest configuration 
sudo systemctl start telegraf

# Setting some vars from script params
SQL_SA_PASSWORD=$1
DATABASE_NAME=$2
echo $DATABASE_NAME

sudo systemctl stop mssql-server
sudo MSSQL_SA_PASSWORD=$SQL_SA_PASSWORD /opt/mssql/bin/mssql-conf set-sa-password
sudo systemctl start mssql-server

# time to sleep
echo "Created by Marek.Start sleep." | sudo dd of=/tmp/terraformsleepstart &> /dev/null
sleep 30m
echo "Created by Marek.Stop sleep." | sudo dd of=/tmp/terraformsleepend &> /dev/null


