# ##############################################################################
# MICROSOFT - SCRIPT - POWERSHELL
# NAME: ABRS-AllVMSnapshot.ps1
# 
# AUTHOR:     Nicholas Karwisch, Microsoft
# DATE:       March 23, 2021
# EMAIL:      nikarw@microsoft.com
# CO-AUTHOR:  Nick Outlaw, Microsoft
# DATE:       March 23, 2021
# EMAIL:      christopher.outlaw@microsoft.com
# 
# COMMENT:  This script will snapshot all virtual machines in all subscriptions
#           and snapshot VM's into a singular resource group. Logs are
#           generated next to the script in log.txt
#
# REQUIRES: Azure Powershell https://www.powershellgallery.com/packages/Az/5.7.0
#
# VERSION HISTORY
# 1.0 March 23, 2021 Initial Version.
#
# ##############################################################################


#Error Log Declare
Function Log {
    param(
        [Parameter(Mandatory=$true)][String]$msg
    )
    
    Add-Content log.txt $msg
}

#Get all subscriptions and assign to variable.
$subs = Get-AzSubscription

#Loop through every subscription
foreach ($sub in $subs)
    {
        #Set subscription ID to dedicated variable
        $SubId = $sub.id

        #Select the subscription ID using the dedicated variable
        Select-AzSubscription -SubscriptionId $SubId

        #Notify user of selected subscription
        Write-Host "Selected subscription ID '$SubId'" -ForegroundColor Green
        $TimeStamp = Get-Date -Format "MM/dd/yyyy | HH:mm:ss "
        $CompiledLogString = $TimeStamp + "| $SubId | " + "Selected subscription ID '$SubId'"
        Log $CompiledLogString

        #Notify user that we are creating a resource group and locking it from delete operations
        Write-Host "INFO : Creating resource group and placing delete lock on the newly created resource group " -ForegroundColor Green
        $TimeStamp = Get-Date -Format "MM/dd/yyyy | HH:mm:ss "
        $CompiledLogString = $TimeStamp + "| $SubId | " + "Checking subscription '$SubId' for resource group, and creating if it does not exist."
        Log $CompiledLogString
        
        #Get resource groups in selected subscription
        Get-AzResourceGroup -Name RecoveryBackup-RG-SCUS -ErrorVariable notPresent -ErrorAction SilentlyContinue
        $TimeStamp = Get-Date -Format "MM/dd/yyyy | HH:mm:ss "
        $CompiledLogString = $TimeStamp + "| $SubId | " + "Querying for resource group named 'RecoveryBackup-RG-SCUS' in '$SubId'"
        Log $CompiledLogString

        #Check if resource group is present
        if ($notPresent)
        {
            try {
                    $TimeStamp = Get-Date -Format "MM/dd/yyyy | HH:mm:ss "
                    $CompiledLogString = $TimeStamp + "| $SubId | " + "Resource group 'RecoveryBackup-RG-SCUS' does not exist in '$SubId'"
                    Log $CompiledLogString

                    #If resource group does not exist, create resource group and lock it from delete operations
                    New-AzResourceGroup -Name RecoveryBackup-RG-SCUS -Location "South Central US"
                    New-AzResourceLock -LockName RecoveryGroupLock -LockLevel CanNotDelete -ResourceGroupName RecoveryBackup-RG-SCUS -Force
                    
                    $TimeStamp = Get-Date -Format "MM/dd/yyyy | HH:mm:ss "
                    $CompiledLogString = $TimeStamp + "| $SubId | " + "Created resource group named 'RecoveryBackup-RG-SCUS' in "
                    Log $CompiledLogString
                }
            catch
                {
                    $TimeStamp = Get-Date -Format "MM/dd/yyyy | HH:mm:ss "
                    $CompiledLogString = $TimeStamp + "| $SubId | " + $_.Exception.Message
                    Log $CompiledLogString
                    Write-Host "There was an error performing resource group provisioning. Error logged."
                }

        }
        else #If resource group is present
        {
            #Notify user that the resource group already exists.
            Write-Host "Resource group already exists in subscription '$SubId'. Skipping resource group creation." -ForegroundColor Yellow
            $TimeStamp = Get-Date -Format "MM/dd/yyyy | HH:mm:ss "
            $CompiledLogString = $TimeStamp + "| $SubId | " + "Resource group named 'RecoveryBackup-RG-SCUS' already exists in subscription '$SubId'. Proceeding."
            Log $CompiledLogString
        }
        
        #Notify user that we are starting backup of all VM's in the subscription
        Write-Host "============================="
        Write-Host "Starting backup for all VM disks in '$sub'" -ForegroundColor Green
        $TimeStamp = Get-Date -Format "MM/dd/yyyy | HH:mm:ss "
        $CompiledLogString = $TimeStamp + "| $SubId | " + "Resource group provisionining complete for subscription '$SubId'. Proceeding with snapshot jobs."
        Log $CompiledLogString

        #Get all virtual machine objects and assign to variable
        $VMs = Get-AzVM
        $VMNames = $VMs.name -join ", "
        $TimeStamp = Get-Date -Format "MM/dd/yyyy | HH:mm:ss "
        $CompiledLogString = $TimeStamp + "| $SubId | " + "List of virtual machines being snapshotted: $VMNames"
        Log $CompiledLogString

        #Loop through each VM and run backup of disks
        foreach ($VM in $VMs)
            {
                $VMName = $VM.Name.ToString() #Get VM name of selected VM
                $VM.Location #Get VM location of selected VM
                Write-Host "Snapshotting $VMName" #Notify user we are snapshotting the selected VM

                $TimeStamp = Get-Date -Format "MM/dd/yyyy | HH:mm:ss "
                $CompiledLogString = $TimeStamp + "| $SubId | " + "Starting snapshot job for VM: $VMName"
                Log $CompiledLogString

                $DiskList = [System.Collections.ArrayList]@() #Add disks to array (OS and Data)
                
                #Add OS disk
                $DiskList.Add($Vm[0].StorageProfile.OSDisk.ManagedDisk.Id)

                #Get full disk lists
                foreach ($disk in $VM[0].StorageProfile.DataDisks)
                    {
                    $DiskInfo = Get-AzDisk -Name $Disk.Name


                    $DiskList.Add($diskinfo.Id)
                    }

                #Set disk count to 0 and add +1 each time a disk is set for snapshot
                $diskcount = 0
                
                #Select all disks under the VM
                foreach ($Disk in $DiskList)
                    {
                        #Start configuring the details on disk for the snapshot job
                        $snapshot = New-AzSnapshotConfig -SourceUri $Disk -Location $Vm.Location -CreateOption Copy

                        #If diskcount = 0, set OS disk in label and start backup
                        if ($diskCount -eq 0)
                            {
                                Write-Host "OS disk detected..." #Notify user of OS disk snapshot
                                $Date = Get-Date -Format "MM-dd-yyyy_THH-mm-ss" #Get current date and time
                                $SnapshotName = $VM.Name + "_OSDiskSnapshot_" + $Date #Set snapshot filename for config
                            }

                        #If diskcount != 0, set Data Disk label
                        else
                            {
                                $Date = Get-Date -Format "MM-dd-yyyy_THH-mm-ss" #Get current date and time
                                $SnapshotName = $VM.Name + "_DataDisk_" + $DiskCount.ToString() + "_DiskSnapshot_" + $Date #Set snapshot name for data disk
                            }

                        #Compiled disk snapshot name
                        $Hashtable_InputInfo = @{"Snapshot" = $Snapshot; "SnapshotName" = $SnapshotName}

                        #Notify user that we are starting backup of the disk above.
                        Write-Host "Starting snapshot job... SnapshotName $SnapshotName" 
                        
                        $TimeStamp = Get-Date -Format "MM/dd/yyyy | HH:mm:ss "
                        $CompiledLogString = $TimeStamp + "| $SubId | " + "Starting snapshot job | VM: $VMName | DISK: $SnapshotName"
                        Log $CompiledLogString
                        #Start the snapshot job with above information
                        New-AzSnapshot -Snapshot $Hashtable_InputInfo.Snapshot -SnapshotName $Hashtable_InputInfo.SnapshotName -ResourceGroupName "RecoveryBackup-RG-SCUS" -ErrorAction Stop -AsJob

                        #Set disk count +1
                        $diskcount = $diskCount + 1
                    }
                #Notify user that we finished snapshotting the VM
                Write-host "Finished Snapshotting $VMName"
                Write-Host "============================="
                $TimeStamp = Get-Date -Format "MM/dd/yyyy | HH:mm:ss "
                $CompiledLogString = $TimeStamp + "| $SubId | " + "VM: $VMName | Disk Snapshot jobs have been executed. Proceeding with next VM."
                Log $CompiledLogString
    
                }

            #Notify user that we have snapshotted each VM 
            Write-Host "Subscription level VM backup complete." -ForegroundColor Green
            $TimeStamp = Get-Date -Format "MM/dd/yyyy | HH:mm:ss "
            $CompiledLogString = $TimeStamp + "| $SubId | " + "Virtual Machines under subscription '$subid' have been snapshotted."
            Log $CompiledLogString
        }