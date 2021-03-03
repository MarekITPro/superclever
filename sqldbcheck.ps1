#! /usr/bin/pwsh
# Last edited: 20/01/2021

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
try {
   $context = New-AzStorageContext -SasToken $SASTOKEN -StorageAccountName $azStorageAccName
}
catch
{
   Write-Output "Unable to connect to Azure Storage, $($_.Exception.Message)"
   exit 1;
}
Write-Output 'Getting list backup files from Azure storage.'
$list = Get-AzStorageBlob -container $azStorageContainer -Context $context |Where-Object {($_.lastmodified -ge $(get-date).AddDays(-$lastXDays)) -and ($_.Name -match $dbname)}
$newest = $list|Select-Object -Property Name |Sort-Object -Descending -Property LastModified |Select-Object -First 1
$newestWithoutNumber = $newest.Name -replace '.(\d+).bak',''
Write-Output 'Getting full list of files to restore.'
$fullListToRestore = Get-AzStorageBlob -container $azStorageContainer -Context $context | Where-Object {$_.Name -match $newestWithoutNumber}

# download

foreach ($blob in $fullListToRestore){
   Get-AzStorageBlobContent `
   -Container $azStorageContainer -Blob $blob.Name -Destination /datadrive/backup/ `
   -Context $context
}

if($(get-childitem -path '/datadrive/backup').count -gt 1){
   # restore
   Write-Output 'Starting SQL restore process.'
   $server  = 'localhost'
   $username = 'sa'
   $password = ConvertTo-SecureString $sqlSAPass -AsPlainText -Force
   $sqlCreds = New-Object System.Management.Automation.PSCredential -ArgumentList ($username, $password)
   $BUFiles = Get-ChildItem -Path '/datadrive/backup/*.bak' | Select-Object -ExpandProperty FullName
   Restore-SqlDatabase -ServerInstance $Server -Database $dbName -BackupFile $BUFiles -Credential $sqlCreds -AutoRelocateFile
   #need to restore to /datadrive/restore hence the -Autorelocatefile as we have set /data and /log folders in the init script
   Write-Output 'Starting dbcc checkdb.'
   # run dbcccheck
   $tsql = "DBCC CHECKDB (`"$dbname`")"
   mkdir /tmp/dbcc |out-null
   Invoke-Sqlcmd -Query $tsql -ServerInstance $server -Credential $sqlCreds -Verbose -ErrorAction Continue 2>&1 3>&1 4>&1 | out-file "/tmp/dbcc/$dbname.log"
   Write-Output "Completed dbcc checkdb, check /tmp/dbcc/$dbname.log file for any info/errors."
}
else {
   Write-Host 'No files have been downloaded for db restore.'
}
Write-Host 'PowerShell script completed its run.'


# https://docs.microsoft.com/en-gb/powershell/module/microsoft.powershell.core/about/about_redirection?view=powershell-7.1
