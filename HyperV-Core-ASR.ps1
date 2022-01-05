
# #############################################################################
# MICROSOFT - SCRIPT - POWERSHELL
# NAME: HyperV-Core-ASR.ps1
# 
# AUTHOR:  Nicholas Karwisch, Microsoft
# DATE:    January 3rd, 2021
# EMAIL:   nikarw@microsoft.com
# 
# COMMENT:  This script will completely setup ASR on Hyper-V Core Servers.
#
# REQUIRES: Az.Accounts, Az.RecoveryServices, Az.Resources
#           
#
# VERSION HISTORY
# 1.0 January 3rd, 2021 Initial Version.
#
# #############################################################################

#region FRAMEWORK:[CHOICE] (FUNCTION)
function Get-Selection {
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
#endregion

#region Set vars for system based file references
$localappdata = $env:LOCALAPPDATA
$programfiles = $env:ProgramFiles
$source = "http://aka.ms/downloaddra"
$destination = "$localappdata\Temp\AzureSiteRecoveryProvider.exe"
$folderStamp = (Get-Date).toString("MM.dd.yyyy")
$logDir = "$localappdata\Temp\ASRProvider\Logs"
If(!(Test-Path $logDir))
{
      New-Item -ItemType Directory -Force -Path $logDir
}
$logDirToday = "$localappdata\Temp\ASRProvider\Logs\$folderStamp\"
If(!(Test-Path $logDirToday))
{
      New-Item -ItemType Directory -Force -Path $logDirToday
}
#endregion

#region Logfile Setup
$Logfile = "$logDirToday\HV_LOG_PS-Output.log"
Start-Transcript -Path "$logDirToday\HV_LOG_Transcript.log"
#endregion

#region Connect to Azure
$connect = Connect-AzAccount -UseDeviceAuthentication
#endregion

#region Get system date
$GetDate = (Get-Date -Format MM-dd-yyy) 
$GetDate = $GetDate.Trim()
#endregion


#region [CHOICE]: SUBSCRIPTION DEFINE
#SUBSCRIPTION DECLARE
$SubscriptionChoice = Get-Selection -Options (Get-AzSubscription | Select-Object -ExpandProperty Id ) -Prompt "Select the Azure Subscription ID"
Set-AzContext -SubscriptionID $SubscriptionChoice
$SubscriptionSelect = Get-AzSubscription -SubscriptionId $SubscriptionChoice
Write-Host "Subscription Selected:" -ForegroundColor Yellow 
Write-Host "Name  : " $SubscriptionSelect.Name -ForegroundColor Green
Write-Host "ID    : " $SubscriptionSelect.Id -ForegroundColor Green
Write-Host ""
$SubIdFinal = $SubscriptionSelect.Id
Write-Log "Subscription ID to be used for future commands: $($SubscriptionSelect.Id)" "INFO"
#endregion


#region [CHOICE]: RESOURCE GROUP DEFINE
$resourceGroupChoice = Get-Selection -Options (Get-AzResourceGroup | Select-Object -ExpandProperty ResourceGroupName) -Prompt "Select the Resource Group." 
$resourceGroupSelect = Get-AzResourceGroup -ResourceGroupName $resourceGroupChoice
Write-Host "Resource Group Selected:" -ForegroundColor Yellow
Write-Host "Name  : " $resourceGroupSelect.ResourceGroupName -ForegroundColor Green
Write-Host ""
$RgNameFinal = $resourceGroupSelect.ResourceGroupName
#endregion


#region [CHOICE]: VAULT DEFINE 
$VaultChoice = Get-Selection -Options (Get-AzRecoveryServicesVault -ResourceGroupName $resourceGroupSelect.ResourceGroupName | Select-Object -ExpandProperty Name) -Prompt "Select the recovery services vault containing the Hyper-V Site."
$VaultSelect = Get-AzRecoveryServicesVault -Name $VaultChoice
Write-Host "Recovery Service Vault Selected: " -ForegroundColor Yellow
Write-Host "Name  : " $VaultSelect.Name -ForegroundColor Green
Write-Host ""
$VaultNameFinal = $VaultSelect.Name
Set-AzRecoveryServicesAsrVaultContext -Vault $VaultSelect
#endregion


#region [CHOICE]: HYPER-V SITE DEFINE 
$siteChoice = Get-Selection -Options (Get-AzRecoveryServicesAsrFabric | Select-Object -ExpandProperty Name) -Prompt "Select the Hyper-V Site you would like to add this server to."
$siteSelect = Get-AzRecoveryServicesAsrFabric -Name $siteChoice
Write-Host "Hyper-V Site Selected: " -ForegroundColor Yellow
Write-Host "Name  : " $siteSelect.Name -ForegroundColor Green
Write-Host ""
$SiteSelectFinal = $siteSelect.SiteIdentifier
#endregion


#region Setup WebRequest for Vault Credential Download
$apiVersion = "?api-version=2019-05-13"

#Declare ARM resource
$armResource = "https://management.azure.com"

$AzTokenResult = Get-AzAccessToken

$token = $AzTokenResult.Token

$query = Invoke-WebRequest -UseBasicParsing -Method PUT -Headers @{"authorization"="Bearer $token"} -ContentType "application/json" -Body "{`"certificateCreateOptions`":{`"validityInHours`":120}}" -Uri "$armResource/subscriptions/$SubIdFinal/resourceGroups/$RgNameFinal/providers/Microsoft.RecoveryServices/vaults/$VaultNameFinal/certificates/CN=CB_$VaultNameFinal-$GetDate-vaultcredentials$apiVersion"
$json = $query.Content | ConvertFrom-Json
#endregion


#region Download Vault Credentials File
Write-Host "Downloading VaultCredential File" -ForegroundColor Green
Write-Host ""
$CredFile = Get-AzRecoveryServicesVaultSettingsFile -Vault $VaultSelect -SiteIdentifier $siteSelectFinal -SiteFriendlyName $siteSelect.FriendlyName -Certificate $json.properties.certificate
Write-Host "VaultCredential File Downloaded!" -ForegroundColor Green
Write-Host "Name  : " -ForegroundColor Yellow -NoNewline
Write-Host $CredFile.FilePath -ForegroundColor Green
$credpathFull = $credFile.FilePath
Write-Host ""
#endregion


#region Download ASR Provider
Write-Host "Proceeding with download of ASR Provider." -ForegroundColor Green
Write-Host "Path: " -ForegroundColor Yellow -NoNewline
Write-Host $destination -ForegroundColor Green
Write-Host ""

# Create the HTTP client download request
$httpClient = New-Object System.Net.Http.HttpClient
$response = $httpClient.GetAsync($source)
$response.Wait()
 
# Create a file stream to pointed to the output file destination
$outputFileStream = [System.IO.FileStream]::new($destination, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
 
# Stream the download to the destination file stream
$downloadTask = $response.Result.Content.CopyToAsync($outputFileStream)
$downloadTask.Wait()
 
# Close the file stream
$outputFileStream.Close()
#endregion


#region Extract ASR Provider
$destinationProviderExtracted = "$localappdata\Temp\ASRProvider"
Write-Host "ASR Provider download complete." -ForegroundColor Green
Write-Host ""
Write-Host "Extracting installer to folder: " -ForegroundColor Yellow -NoNewline
Write-Host $destinationProviderExtracted -ForegroundColor Green
Start-Process -NoNewWindow -FilePath "$destination" -ArgumentList "/x:$destinationProviderExtracted /q" -Wait
Write-Host ""
Write-Host "Extraction status: " -ForegroundColor Yellow -NoNewline
Start-Sleep -Seconds 3
Write-Host "ASR Provider extraction complete." -ForegroundColor Green
Write-Host ""
#endregion


#region Ask to start ASR Provider installation
$confirmInstall = Read-Host "ASR Provider is ready for install. Proceed with installation of ASR Provider? (y/n)"
if ($confirmInstall -eq 'y') {
    Write-Host "Proceeding with installation of ASR Provider." -ForegroundColor Green
    Write-Host "Starting install ($destinationProviderExtracted\setupdr.exe /i)" -ForegroundColor Yellow
    Write-Host ""
    Start-Process -NoNewWindow -FilePath "$destinationProviderExtracted\SETUPDR.exe" -ArgumentList "/i" -Wait
    Write-Host "ASR Provider installation complete." -ForegroundColor Green
    
} 
else 
{
    Write-Host "Exiting." -ForegroundColor Red
}
#endregion


#region Ask to start ASR Provider Registration
$confirmRegister = Read-Host "ASR Provider is ready for registration. Proceed with registration? (y/n)"
if ($confirmRegister -eq 'y') {
    Write-Host "Proceeding with registration of ASR Provider." -ForegroundColor Green
    $regFriendlyName = Read-Host "Please enter a Friendly Name for this server. This name will be displayed in the Azure Portal."
    Write-Host ""

    Start-Process -NoNewWindow -FilePath "$programfiles\Microsoft Azure Site Recovery Provider\DRConfigurator.exe" -ArgumentList "/r /Friendlyname $regFriendlyName /Credentials $credpathFull" -Wait
    Write-Host "ASR Provider registration complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "This server should now be displayed in the Azure Portal." -ForegroundColor Green
} 
else 
{
    Write-Host "Exiting." -ForegroundColor Red
}
#endregion


Write-Host "Script complete." -ForegroundColor Green

Stop-Transcript