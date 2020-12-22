#! /bin/bash
# check params :)
if [[ $# -ne 3 ]]; then
    echo "Illegal number of parameters, use: restore_and_check_db.sh sql_sa_password database_name sas_key"
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

echo "set RWX permissions on /datadrive and subs"
sudo chmod -R 777 /datadrive/

echo "download azcopy"
sudo wget -O /datadrive/tools/azcopy_v10.tar.gz https://aka.ms/downloadazcopy-v10-linux 

echo "extract azcopy"
sudo tar -xf /datadrive/tools/azcopy_v10.tar.gz --strip-components=1 -C /datadrive/tools
sudo chmod +x /datadrive/tools/azcopy

# echo "install AzureCLI"
# sudo curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

sleep 1m

# Setting some vars from script params
SQL_SA_PASSWORD=$1
DATABASE_NAME=$2
echo $DATABASE_NAME
SAS_KEY=$3
echo $SAS_KEY

sudo systemctl stop mssql-server
sleep 1m
sudo MSSQL_SA_PASSWORD=$SQL_SA_PASSWORD /opt/mssql/bin/mssql-conf set-sa-password
sleep 1m
sudo systemctl start mssql-server

# time to sleep TODO: make that into param as the required sleep time may be up to 1 hour for AZ to provision access to KV for VM
# echo "Created by Marek.Start sleep." | sudo dd of=/tmp/terraformsleepstart &> /dev/null
# sleep 30m
# echo "Created by Marek.Stop sleep." | sudo dd of=/tmp/terraformsleepend &> /dev/null

echo "install metricbeat"
curl -L -O https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-7.8.1-amd64.deb
sudo dpkg -i metricbeat-7.8.1-amd64.deb
# TODO: auth to ELK stack needs doing here as well

# Access and download backups from storage using azcopy HARDCODED path?
/datadrive/tools/azcopy login --identity
sleep 1m
/datadrive/tools/azcopy copy "https://marekteststorage.blob.core.windows.net/sqlbackups/$DATABASE_NAME.bak$SAS_KEY" "/datadrive/backup/$DATABASE_NAME.bak"
/datadrive/tools/azcopy logout

BACKUP_NAME=`ls -t1 /datadrive/backup/* |head -n 1`
echo $BACKUP_NAME

echo "figure out file names to restore - to be changed"
/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P $SQL_SA_PASSWORD -Q "RESTORE FILELISTONLY FROM DISK='$BACKUP_NAME'" | tail -n +3 |head -n -2|awk '{ print $1 }' > /tmp/restore_fnames.txt
cat /tmp/restore_fnames.txt |  awk 'BEGIN { print "RESTORE DATABASE ['$DATABASE_NAME'] FROM DISK= ~'$BACKUP_NAME'~ WITH FILE=1," } { print "MOVE N\x27"$1"\x27 TO N\x27/datadrive/restore/"$1"\x27, " } END { print "NOUNLOAD, STATS=5" }' >/tmp/restore_3_TSQL.txt
cat /tmp/restore_3_TSQL.txt | tr "~" "'" > /tmp/restore_4_final.sql
cat /tmp/restore_4_final.sql

# Process the TSQL restore /time consiming, storage I/O/
/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P $SQL_SA_PASSWORD -i /tmp/restore_4_final.sql

DB_RESTORE_RESULT="FAILED"
DB_RESTORE_RESULT=`/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P $SQL_SA_PASSWORD -Q "EXEC sp_readerrorlog 0,1,'restore is complete',$DATABASE_NAME" |tail -n +3 |head -n -2 |awk '{ if ($6 == "complete") {print "RESTORED" } }'`
if [ $DB_RESTORE_RESULT != "FAILED" ]; then
    echo "DB restore completed"
else
    echo "DB restore failed"
    exit 2
fi

echo "Run backup integrity check"
echo "dbcc check - starting" | sudo dd of=/tmp/dbccprogress &> /dev/null
/opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P $SQL_SA_PASSWORD -Q "DBCC CHECKDB ($DATABASE_NAME) with no_infomsgs,all_errormsgs"
echo "DBCC check executed"
echo "dbcc check - stopped" | sudo dd of=/tmp/dbccprogress &> /dev/null
