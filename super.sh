#! /bin/bash
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
