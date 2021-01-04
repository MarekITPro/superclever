#! /usr/bin/pwsh

[cmdletbinding()]
param(
   [string]$dbName = "AdventureWorks2017.Sql.Aux.Full",
   [int]$lastXDays = 60,
   [string]$azStorageAccName = 'marekteststorage',
   [string]$azStorageContainer = 'sqlbackups',
   [string]$SASTOKEN = '',
   [string]$sqlSAPass = '')

# Install required PWSH modules
Install-Module -Name Az.Storage,SQLServer -Force

# Get list of files for given database from AZ Blob
$context = New-AzStorageContext -SasToken $SASTOKEN -StorageAccountName $azStorageAccName
$list = Get-AzStorageBlob -container $azStorageContainer -Context $context |Where-Object {($_.lastmodified -ge $(get-date).AddDays(-$lastXDays)) -and ($_.Name -match $dbname)}
$newest = $list|Select-Object -Property Name |Sort-Object -Descending -Property LastModified |Select-Object -First 1
$newestWithoutNumber = $newest.Name -replace '.(\d+).bak',''
$fullListToRestore = Get-AzStorageBlob -container $azStorageContainer -Context $context | Where-Object {$_.Name -match $newestWithoutNumber} |Select-Object -Property Name

# download
$fullListToRestore | Get-AzStorageBlobContent -Destination '/datadrive/backup/'

if($(get-childitem -path '/datadrive/backup').count -gt 1){

   # restore
$server  = 'localhost'
$username = 'sa'
$password = ConvertTo-SecureString $sqlSAPass -AsPlainText -Force
$sqlCreds = New-Object System.Management.Automation.PSCredential -ArgumentList ($username, $password)
$BUFiles = Get-ChildItem -Path '/datadrive/backup/*.bak' | Select-Object -ExpandProperty FullName
Restore-SqlDatabase -ServerInstance $Server -Database $dbName -BackupFile $BUFiles -Credential $sqlCreds -AutoRelocateFile
#need to restore to /datadrive/restore hence the -Autorelocatefile as we have set /data and /log folders in the init script

# run dbcccheck
$tsql = "DBCC CHECKDB (`"$dbname`") with no_infomsgs,all_errormsgs"
Invoke-Sqlcmd -Query $tsql -ServerInstance $server -Credential $sqlCreds |out-file "/tmp/$dbname.dbcc.rpt"
}
else {
   Write-Host 'No files have been downloaded for db restore'
}
