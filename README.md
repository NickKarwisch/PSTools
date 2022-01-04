# PSTools
Powershell scripts that I have worked on or am currently working on will be contained here.


## AzureBackup-RecoveryPointQuery.ps1
### Recovery Point Query Script Description:
This script will walk through the process of pulling recovery points through a guided process via user input.

### Recovery Point Query Script Example:
![Recovery Point Query](https://github.com/NAKarwisch/PSTools/blob/master/ex/RPGather.PNG?raw=true)


## ABRS-AllVMSnapshot.ps1
### ABRS All VM Snapshot Description:
This script will snapshot all virtual machines in every subscription you have access to and place the snapshotted disks for each machine in a singular resource group.


## HyperV-Core-ASR.ps1
### ASR Hyper-V Provider Install and Register Script:
This script will walk through the process of logging into Azure and selecting your Subscription, Resource Group, and Vault. Then the script will download the VaultCredentials file, download the ASR Provider via http://aka.ms/downloaddra and then install the ASR Provider. After installation is complete, the software is then registered to the selected vault under the subscription selected.
