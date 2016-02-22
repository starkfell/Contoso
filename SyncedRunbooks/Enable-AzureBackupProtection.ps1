<#

    .SYNOPSIS
       Adds Azure VM to Azure Backup Policy to enable
       protection.

    .DESCRIPTION
       Adds Azure VM to Azure Backup Policy to enable
       protection. It uses Azure RM cmdlets.

    .PARAMETER  VMName
	   Mandatory parameter. This parameter is used for 
       finding the Azure VM that will be added to 
       backup policy.

    .PARAMETER  BackupPolicyName
	   Mandatory parameter. This parameter is used for 
       finding the backup policy to which the Azure VM
       will be added.

    .PARAMETER  VaultName
	   Not mandatory parameter. This parameter is used for 
       finding the Backup policy. If not specified
       value will be taken from variable in Automation
       Asset store.
       
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
workflow Enable-AzureBackupProtection
{
    param (
        [Parameter(Mandatory=$true)]
        [String] 
        $VMName,

        [Parameter(Mandatory=$true)]
        [String] 
        $BackupPolicyName,

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
            $BackupPolicyName    = $WebhookBodyObj.BackupPolicyName
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
    inlinescript
    {
        Try
        {
            # Connect to Azure
            $AzureAccount = Add-AzureRmAccount `
                            -Credential $Using:AzureCreds `
                            -SubscriptionId $Using:AzureSubscriptionID `
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
                 -Name $Using:VaultName `
                 -ErrorAction Stop
        if ($Vault.Count -eq 0)
        {
            $ErrorMessage = 'Backup Vault was not found.'
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }



        Try
        {
            # Get Backup Policy
            $BackupPolicy = Get-AzureRmBackupProtectionPolicy `
                            -Vault $Vault `
                            -Name $Using:BackupPolicyName `
                            -ErrorAction Stop
        }
        Catch
        {
            $ErrorMessage = 'Failed to get Azure Backup Policy.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }
    
        Try
        {
            # Enable Protection
            $ProtectionEnabled = Get-AzureRmBackupContainer `
                                 -Vault $Vault `
                                 -Type AzureVM `
                                 -Status Registered `
                                 -Name $Using:VMName `
                                 -ErrorAction Stop | `
                                 Get-AzureRmBackupItem `
                                 -ErrorAction Stop | `
                                 Enable-AzureRmBackupProtection `
                                 -Policy $BackupPolicy `
                                 -ErrorAction Stop
            Write-Output -InputObject 'Protection of Azure VM was enabled.'
        }
        Catch
        {
            $ErrorMessage = 'Failed to enable proection on Backup on Azure VM.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }
    }
    


}