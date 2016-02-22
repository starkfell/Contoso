<#

    .SYNOPSIS
       Creates new Azure Backup Vault from AzureRM cmdlets.

    .DESCRIPTION
       Creates new Azure Backup Vault from AzureRM cmdlets.
       It also sets value in Automation Assets store for
       variable BackupVaultName.

    .PARAMETER  VaultName
	   Mandatory parameter. This parameter is used for 
       providing name for the Azure Backup Vault.

    .PARAMETER  VaultResourceGroup
	   Mandatory parameter. This parameters is used for
       placing the Azure Backup Vault in Azure Resource Group.
       If the resource Group does not exists it will be created.

    .PARAMETER  VaultRegion
	   Mandatory parameter. This parameter is used for
       placign the Azure Backup vault in a region. The same
       region is used for the Resource Group if it is created.
       
    .PARAMETER  VaultStorageType
	   Mandatory parameter. This parameter is used for
       designating the Azure Backup Vault Storage Type.
       Supported values are GeoRedundant or LocallyRedundant.
       
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
workflow  New-AzureBackupVault
{
    param (
        [Parameter(Mandatory=$true)]
        [String] 
        $VaultName,

        [Parameter(Mandatory=$true)]
        [String] 
        $VaultResourceGroup,

        [Parameter(Mandatory=$true)]
        [String] 
        $VaultRegion,
        
        [Parameter(Mandatory=$true)]
        [String] 
        $VaultStorageType,

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
            $VaultName           = $WebhookBodyObj.VaultName 
            $VaultResourceGroup  = $WebhookBodyObj.VaultResourceGroup
            $VaultRegion         = $WebhookBodyObj.VaultRegion
            $VaultStorageType    = $WebhookBodyObj.VaultStorageType
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
        Write-Output 'Successfuly connected to Azure.'
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
    
    Try
    {
        $RG = Get-AzureRmResourceGroup `
              -Name $VaultResourceGroup `
              -ErrorAction Stop
    
    }
    Catch
    {
        Try
        {
            # Create RG
            $RG = New-AzureRmResourceGroup `
                  -Name $VaultResourceGroup `
                  -Location $VaultRegion `
                  -ErrorAction Stop
            Write-Output -InputObject 'Successfully created Resource Group.'
        }
        Catch
        {
            $ErrorMessage = 'Failed to create Resource Group.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }
    }
    
    Try
    {
        # Create Vault
        $BackupVault = New-AzureRmBackupVault `
                       -ResourceGroupName $VaultResourceGroup `
                       -Name $VaultName `
                       -Region $VaultRegion `
                       -Storage $VaultStorageType `
                       -ErrorAction Stop             #GeoRedundant LocallyRedundant
        Write-Output 'Successfully created Backup Vault.'
    }
    Catch
    {
        $ErrorMessage = 'Failed to create Backup Vault.'
        $ErrorMessage += " `n"
        $ErrorMessage += 'Error: '
        $ErrorMessage += $_
        Write-Error -Message $ErrorMessage `
                    -ErrorAction Stop
    }
    Try
    {
        Set-AutomationVariable `
         -Name 'BackupVaultName' `
         -Value $VaultName
    }
    Catch
    {
        # skip
    }

}