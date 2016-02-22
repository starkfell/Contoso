<#

    .SYNOPSIS
       Register Azure Classic VM to Azure Backup Vault.

    .DESCRIPTION
       Register Azure Classic VM to Azure Backup Vault.
       Uses Azure RM cmdlets. Azure V2 VMs are currently
       not supported by Azure Backup. The Azure Classic
       VM needs to be created from Azure Resource Manager
       portal to be registered to Azure Backup Vault.

    .PARAMETER  VMName
	   Mandatory parameter. This parameter is used for 
       finding the Azure Classic VM that will be added
       to Azure Backup Vault.

    .PARAMETER  VMResourceGroup
	   Mandatory parameter. This parameter is used for 
       finding in which Resource Group is the Azure
       Classic VM.

    .PARAMETER  VaultName
	   Not mandatory parameter. This parameter is used for 
       placing the Azure Classic VM in Azure Backup Vault.
       If not specified value will be taken from variable 
       in Automation Asset store.
       
    .PARAMETER  AzureSubscriptionID
	   Not mandatory parameter. This parameter is used for
       designating the Azure subscription under which will
       be operated. If this parameter is not specified
       value will be taken from Variable in Automation Asset
       Store.
       
    .PARAMETER  WebhookData
	   Not mandatory parameter. This parameter is used
       if webhook is enabled for the runbook. In that case
       all other parameters are passed through WebhookData
       parameter. To make the runbook more secure there is
       authorization value 'Contoso' that needs to be provided.
       In case that vale is not provided the runbook will fail.
    
    .OUTPUTS
        Outputs result message for the workflow.
#>
workflow Register-AzureClassicVMToAzureBackup
{
    param (
        [Parameter(Mandatory=$true)]
        [String] 
        $VMName,

        [Parameter(Mandatory=$true)]
        [String] 
        $VMResourceGroup,

        [Parameter(Mandatory=$false)]
        [String] 
        $VaultName,

        [Parameter(Mandatory=$false)]
        [String] 
        $AzureSubscriptionID,

        [Parameter(Mandatory=$false)]
        [object] 
        $WebhookData
                   
    )

    # Set Error Preference	
	$ErrorActionPreference = "Stop"

    # When webhook is used
    if ($WebhookData -ne $null) 
    {
        # Collect properties of WebhookData
        $WebhookName    =   $WebhookData.WebhookName
        $WebhookHeaders =   $WebhookData.RequestHeader
        $WebhookBody    =   $WebhookData.RequestBody

        $AuthorizationValue = $WebhookHeaders.AuthorizationValue
        If ($AuthorizationValue -eq 'Contoso')
        {
            # Convert webhook body
            $WebhookBodyObj = ConvertFrom-Json `
                                -InputObject $WebhookBody `
                                -ErrorAction Stop
        
            # Get webhook input data
            $VMName              = $WebhookBodyObj.VMName
            $VMResourceGroup     = $WebhookBodyObj.VMResourceGroup
            $VaultName           = $WebhookBodyObj.VaultName
            $AzureSubscriptionID = $WebhookBodyObj.AzureSubscriptionID
        }
        Else
        {
            $ErrorMessage = 'Webhook was executed without authorization.'
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }
        
    }

    # Check if AzureSubscriptionID exists
    If ($AzureSubscriptionID -eq $null)
    {
        $AzureSubscriptionID = Get-AutomationVariable `
                               -Name 'AzureSubscriptionID'
    }

    # Check if VaultName exists
    If ($VaultName -eq $null)
    {
        $VaultName = Get-AutomationVariable `
                     -Name 'BackupVaultName'
    }
    
    # Get Credentials to Azure Subscription
    $AzureCreds = Get-AutomationPSCredential `
                  -Name 'AzureCredentials'

    Try
    {
        # Connect to Azure
        $AzureAccount = Add-AzureRmAccount `
                        -Credential $AzureCreds `
                        -SubscriptionId $AzureSubscriptionID `
                        -ErrorAction Stop
        Write-Output -InputObject 'Successfuly connected to Azure.'
    }
    Catch
    {
        $ErrorMessage = 'Login to Azure failed.'
        $ErrorMessage += " `n"
        $ErrorMessage += 'Error: '
        $ErrorMessage += $_
        Write-Error -Message $ErrorMessage `
                    -ErrorAction Stop
    }

    # Get Vault
    $Vault = Get-AzureRmBackupVault `
             -Name $VaultName `
             -ErrorAction Stop
    if ($Vault.Count -eq 0)
    {
        $ErrorMessage = 'Backup Vault was not found.'
        Write-Error -Message $ErrorMessage `
                    -ErrorAction Stop
    }

    Try
    {
        # Register Classic VM to Azure Backup
        $RegisterVMBackup = Register-AzureRmBackupContainer `
                             -ResourceGroupName $VMResourceGroup `
                             -Name $VMName `
                             -Vault $Vault `
                             -ErrorAction Stop
        Write-Output -InputObject 'Registration of Azure VM to Azure Backup has started.'
        
        # Wait for registration completion
        $IsRegistered = $false
        $i = 0 
        Do
        {
            $i++
            $BackupContainer = Get-AzureRmBackupContainer `
                               -Type AzureVM `
                               -Vault $Vault `
                               -Name $VMName `
                               -ErrorAction Stop
            If ($BackupContainer.Status -eq 'Registered')
            {
                $IsRegistered = $true
                Write-Output -InputObject 'Classic Azure VM was successfully registered to Azure Backup.'
            }
            If ($i -gt 120) 
            {
                $ErrorMessage = 'Job for registering Azure Classic VM to Azure backup timed out.'
                $ErrorMessage += " `n"
                $ErrorMessage += 'Error: '
                $ErrorMessage += $_
                Write-Error -Message $ErrorMessage `
                            -ErrorAction Stop
            }
            Start-Sleep -Seconds 5
        } while ($IsRegistered -eq $false)

    }
    Catch
    {
        $ErrorMessage = 'Failed to register Classic Azure VM to Azure Backup.'
        $ErrorMessage += " `n"
        $ErrorMessage += 'Error: '
        $ErrorMessage += $_
        Write-Error -Message $ErrorMessage `
                    -ErrorAction Stop
    }

    

}