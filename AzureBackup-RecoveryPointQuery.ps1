# #############################################################################
# MICROSOFT - SCRIPT - POWERSHELL
# NAME: AzureBackup-RecoveryPointQuery.ps1
# 
# AUTHOR:  Nicholas Karwisch, Microsoft
# DATE:    May 29, 2020
# EMAIL:   nikarw@microsoft.com
# 
# COMMENT:  This script will walk through your subscription to pull
#           recovery points based on user input.
#
# REQUIRES: Azure Powershell Module
#           https://docs.microsoft.com/en-us/powershell/azure/install-az-ps
#
# VERSION HISTORY
# 1.0 May 29, 2020 Initial Version.
#
# #############################################################################

function Get-SelectionFromUser {
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$Options,
        [Parameter(Mandatory=$true)]
        [string]$Prompt        
    )
    
    [int]$Response = 0;
    [bool]$ValidResponse = $false    

    while (!($ValidResponse)) {            
        [int]$OptionNo = 0

        Write-Host $Prompt -ForegroundColor DarkYellow
        Write-Host "[0]: Cancel"

        foreach ($Option in $Options) {
            $OptionNo += 1
            Write-Host ("[$OptionNo]: {0}" -f $Option)
        }

        if ([Int]::TryParse((Read-Host), [ref]$Response)) {
            if ($Response -eq 0) {
                return ''
            }
            elseif($Response -le $OptionNo) {
                $ValidResponse = $true
            }
        }
    }

    return $Options.Get($Response - 1)
} 

#Connect-AzAccount

#SUBSCRIPTION DECLARE
$Subscription = Get-AzSubscription
$SubscriptionChoice = Get-SelectionFromUser -Options ($Subscription.Id) -Prompt "Select the Azure Subscription ID"
Set-AzContext -SubscriptionID $SubscriptionChoice
$SubscriptionDetails = Get-AzSubscription -SubscriptionId $SubscriptionChoice
Write-Host "Subscription selected:" -ForegroundColor Yellow
Write-Host "Name: " $SubscriptionDetails.Name -ForegroundColor Green
Write-Host "ID : " $SubscriptionDetails.Id -ForegroundColor Green
Write-Host ""

#DATE DECLARE
$StartDateSelect = Read-Host -Prompt "Number of days to pull recovery points in the past?"
$StartDate = (Get-Date).AddDays(-$StartDateSelect) 
$EndDate = Get-Date 
Write-Host "Dates selected:" -ForegroundColor Yellow
Write-Host "START : " $StartDate.ToUniversalTime() -ForegroundColor Green
Write-Host "END : " $EndDate.ToUniversalTime() -ForegroundColor Green
Write-Host ""

#VAULT DECLARE
$Vault = Get-AzRecoveryServicesVault
$VaultChoice = Get-SelectionFromUser -Options ($Vault.Name) -Prompt "Select the Vault to query against:"
$VaultSelect = Get-AzRecoveryServicesVault -Name $VaultChoice
Write-Host "Selected Vault: " -ForegroundColor Yellow
Write-Host $VaultName -ForegroundColor Green
$VaultId = $VaultSelect.ID
Write-Host ""
Write-Host "Attaching Vault ID to Variable. " -ForegroundColor Yellow
Write-Host "Result: "$VaultId -ForegroundColor Green

#CONTAINER DECLARE
$ContainerType = Get-SelectionFromUser -Options ('AzureVM','AzureSQL','AzureStorage','AzureVMAppContainer','Windows') -Prompt "Select the Container Type to query against:"
Write-Host "Querying Vault:" $VaultChoice "for container type:" $ContainerType -ForegroundColor Green
$Container = Get-AzRecoveryServicesBackupContainer -VaultId $VaultId -ContainerType $ContainerType -Status Registered
$ContainerChoice = Get-SelectionFromUser -Options ($Container.FriendlyName) -Prompt "Select the Container:"
$ContainerFriendlyName = $ContainerChoice
$ContainerSelect = Get-AzRecoveryServicesBackupContainer -VaultId $VaultId -ContainerType $ContainerType -Status Registered -FriendlyName $ContainerFriendlyName
Write-Host "Container Type: " -ForegroundColor Yellow
Write-Host $ContainerType -ForegroundColor Green
Write-Host ""
Write-Host "Container Selected: " -ForegroundColor Yellow
Write-Host $ContainerChoice -ForegroundColor Green
Write-Host ""

#BACKUPITEM DECLARE
$BackupItemWorkloadType = Get-SelectionFromUser -Options ('AzureVM','AzureFiles','AzureSQLDatabase','MSSQL') -Prompt "Select the Workload Type to query against:"
Write-Host "Querying Container:" $ContainerSelect.Name "for workload type:" $BackupItemWorkloadType -ForegroundColor Green
$BackupItem = Get-AzRecoveryServicesBackupItem -VaultId $VaultId -WorkloadType $BackupItemWorkloadType -Container $ContainerSelect
$BackupItemChoice = Get-SelectionFromUser -Options ($BackupItem.Name) -Prompt "Select a backup item to view recovery points for:"
$BackupItemSelect = Get-AzRecoveryServicesBackupItem -VaultId $VaultId -WorkloadType $BackupItemWorkloadType -Container $ContainerSelect -Name $BackupItemChoice
Write-Host "Selecting the backup item matching:" -ForegroundColor Yellow
Write-Host $BackupItemChoice -ForegroundColor Green

#GATHER RECOVERY POINTS
Write-Host "Full Query:" -ForegroundColor Yellow
Write-Host "--------------------" -ForegroundColor Yellow
Write-Host "Subscription Name   : " -ForegroundColor Yellow -NoNewline; Write-Host $SubscriptionDetails.Name -ForegroundColor Green
Write-Host "Subscription I      : " -ForegroundColor Yellow -NoNewline; Write-Host $SubscriptionDetails.Id -ForegroundColor Green
Write-Host "Start Date          : " -ForegroundColor Yellow -NoNewline; Write-Host $StartDate.ToUniversalTime() -ForegroundColor Green
Write-Host "End Date            : " -ForegroundColor Yellow -NoNewline; Write-Host $EndDate.ToUniversalTime() -ForegroundColor Green
Write-Host "Vault Name          : " -ForegroundColor Yellow -NoNewline; Write-Host $Vault.Name -ForegroundColor Green
Write-Host "Container Type      : " -ForegroundColor Yellow -NoNewline; Write-Host $ContainerType -ForegroundColor Green
Write-Host "Container Name      : " -ForegroundColor Yellow -NoNewline; Write-Host $ContainerSelect.FriendlyName -ForegroundColor Green
Write-Host "Workload Type       : " -ForegroundColor Yellow -NoNewline; Write-Host $BackupItemWorkloadType -ForegroundColor Green
Write-Host "Backup Item Name    : " -ForegroundColor Yellow -NoNewline; Write-Host $BackupItemChoice -ForegroundColor Green

$RunQuery = Read-Host -Prompt 'Ready to query? (y/n)'
if ($RunQuery = "y") {
    Write-Host "Querying for recovery points using the full query information from above." -ForegroundColor Green
	$RP = Get-AzRecoveryServicesBackupRecoveryPoint -VaultId $VaultId -Item $BackupItemSelect -StartDate $StartDate.ToUniversalTime()  -EndDate $EndDate.ToUniversalTime()
    $title = 'Recovery Points for '+ $BackupItemChoice + ' | From ' + $StartDate.ToUniversalTime() + ' TO ' + $EndDate.ToUniversalTime()
    $RP | Select-Object -Property ItemName, RecoveryPointType, RecoveryPointTime, RecoveryPointId, ContainerName | Sort-Object -Property RecoveryPointTime -Descending | Out-GridView -Title $title
} else {
	Write-Warning -Message "Canceling."
    $Repeat = $False
}