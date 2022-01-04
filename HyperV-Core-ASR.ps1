
# #############################################################################
# MICROSOFT - SCRIPT - POWERSHELL
# NAME: HyperV-Core-ASR.ps1
# 
# AUTHOR:  Nicholas Karwisch, Microsoft
# DATE:    December 30th, 2021
# EMAIL:   nikarw@microsoft.com
# 
# COMMENT:  This script will completely setup ASR on Hyper-V Core Servers.
#
# REQUIRES: Az
#           
#
# VERSION HISTORY
# 1.0 December 30th, 2021 Initial Version.
#
# #############################################################################



##### Predefine custom choice framework #####
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

Connect-AzAccount

#Setup Parameters

#DATE DECLARE
$GetDate = (Get-Date -Format MM-dd-yyy)
$GetDate = $GetDate.Trim()

#SUBSCRIPTION DECLARE
$SubscriptionChoice = Get-Selection -Options (Get-AzSubscription | Select-Object -ExpandProperty Id) -Prompt "Select the Azure Subscription ID"
Set-AzContext -SubscriptionID $SubscriptionChoice
$SubscriptionSelect = Get-AzSubscription -SubscriptionId $SubscriptionChoice
Write-Host "Subscription Selected:" -ForegroundColor Yellow
Write-Host "Name  : " $SubscriptionSelect.Name -ForegroundColor Green
Write-Host "ID    : " $SubscriptionSelect.Id -ForegroundColor Green
Write-Host ""
$SubIdFinal = $SubscriptionSelect.Id


$resourceGroupChoice = Get-Selection -Options (Get-AzResourceGroup | Select-Object -ExpandProperty ResourceGroupName) -Prompt "Select the Resource Group."
$resourceGroupSelect = Get-AzResourceGroup -ResourceGroupName $resourceGroupChoice
Write-Host "Resource Group Selected:" -ForegroundColor Yellow
Write-Host "Name  : " $resourceGroupSelect.ResourceGroupName -ForegroundColor Green
Write-Host ""
$RgNameFinal = $resourceGroupSelect.ResourceGroupName


#VAULT DECLARE
$VaultChoice = Get-Selection -Options (Get-AzRecoveryServicesVault -ResourceGroupName $resourceGroupSelect.ResourceGroupName | Select-Object -ExpandProperty Name) -Prompt "Select the recovery services vault containing the Hyper-V Site."
$VaultSelect = Get-AzRecoveryServicesVault -Name $VaultChoice
Write-Host "Selected Vault: " -ForegroundColor Yellow
Write-Host $VaultSelect.Name -ForegroundColor Green
Write-Host ""
$VaultNameFinal = $VaultSelect.Name

#Declare API Version
$apiVersion = "?api-version=2019-05-13"

#Declare ARM resource
$armResource = "https://management.azure.com"

$AzTokenResult = Get-AzAccessToken

$token = $AzTokenResult.Token

$headers = @{
    'authorization' = "Bearer $token"
}

$query = Invoke-WebRequest -UseBasicParsing -Method PUT -Headers $headers -ContentType "application/json" -Body "{`"certificateCreateOptions`":{`"validityInHours`":120}}" -Uri "$armResource/subscriptions/$SubIdFinal/resourceGroups/$RgNameFinal/providers/Microsoft.RecoveryServices/vaults/$VaultNameFinal/certificates/CN=CB_$VaultNameFinal-$GetDate-vaultcredentials$apiVersion"
$json = $query.Content | ConvertFrom-Json

Write-Host "Downloading VaultCredential File" -ForegroundColor Green
Write-Host ""

$CredFile = Get-AzRecoveryServicesVaultSettingsFile -Vault $VaultSelect -Certificate $json.properties.certificate

Write-Host "VaultCredential File Downloaded!" -ForegroundColor Green
Write-Host "Path: " -ForegroundColor Yellow -NoNewline
Write-Host $CredFile.FilePath -ForegroundColor Green
Write-Host ""


$localappdata = $env:LOCALAPPDATA
$programfiles = $env:ProgramFiles
$source = "http://aka.ms/downloaddra"
$destination = "$localappdata\Temp\AzureSiteRecoveryProvider.exe"


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


$confirmRegister = Read-Host "ASR Provider is ready for registration. Proceed with registration? (y/n)"
if ($confirmRegister -eq 'y') {
    Write-Host "Proceeding with registration of ASR Provider." -ForegroundColor Green
    $regFriendlyName = Read-Host "Please enter a Friendly Name for this server. This name will be displayed in the Azure Portal."
    Write-Host ""

    Start-Process -NoNewWindow -FilePath "$programfiles\Microsoft Azure Site Recovery Provider\DRConfigurator.exe" -ArgumentList "/r /Friendlyname '$regFriendlyName' /Credentials '$credFile'" -Wait
    Write-Host "ASR Provider registration complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "This server should now be displayed in the Azure Portal." -ForegroundColor Green
} 
else 
{
    Write-Host "Exiting." -ForegroundColor Red
}

Write-Host "Script complete." -ForegroundColor Green

