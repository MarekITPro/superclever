#! /bin/bash
# check params - must be two :)
if [[ $# -ne 2 ]]; then
    echo "Illegal number of parameters, usage: restore_and_check_db.sh sql_sa_password database_name"
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

echo "format disk"
sudo mkfs -t ext4 /dev/disk/azure/scsi1/lun0-part1

echo "mount"
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
