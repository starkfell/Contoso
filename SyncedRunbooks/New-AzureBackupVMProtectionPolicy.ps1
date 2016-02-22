<#

    .SYNOPSIS
       Creates new Azure Backup Policy with Daily and Monthly
       retention periods.

    .DESCRIPTION
       Creates new Azure Backup Policy with Daily and Monthly
       retention periods. It uses Azure RM cmdlets.

    .PARAMETER  BackupPolicyName
	   Mandatory parameter. This parameter is used for 
       providing name for the Azure Backup Policy.

    .PARAMETER  BackupTime
	   Mandatory parameter. This parameter is used for 
       providing time value when backups will start.
       Example values are 03:15 or 03:15 AM .

    .PARAMETER  DailyRetentionPeriod
	   Mandatory parameter. This parameter is used for 
       providing retention period of Daily Backups.
       Example value is 30 which will keep daily 
       backups for 30 days.

    .PARAMETER  MonthlyRetentionPeriod
	   Mandatory parameter. This parameter is used for 
       providing retention period of Monthly Backups.
       Example value is 12 which will keep daily 
       backups for 1 year.

    .PARAMETER  DaysOfMonth
	   Mandatory parameter. This parameter is used for 
       providing days of the monthly backup to occur.
       Multiple values can be specified. Example value is
       (10, 20) which will make monthly backups on 10th and
       20th day of the month.
    
    .PARAMETER  VaultName
	   Not mandatory parameter. This parameter is used for 
       creating the backup policy in specific Vault. If not 
       specified value will be taken from variable in 
       Automation Asset store.
       
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
workflow New-AzureBackupVMProtectionPolicy
{
    param (
        [Parameter(Mandatory=$true)]
        [String] 
        $BackupPolicyName,

        [Parameter(Mandatory=$true)]
        [String] 
        $BackupTime,

        [Parameter(Mandatory=$true)]
        [int] 
        $DailyRetentionPeriod,

        [Parameter(Mandatory=$true)]
        [int] 
        $MonthlyRetentionPeriod,
        
        [Parameter(Mandatory=$true)]
        [String] 
        $DaysOfMonth,
        
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
            $BackupPolicyName       = $WebhookBodyObj.BackupPolicyName
            $BackupTime             = $WebhookBodyObj.BackupTime
            $DailyRetentionPeriod   = $WebhookBodyObj.DailyRetentionPeriod
            $MonthlyRetentionPeriod = $WebhookBodyObj.MonthlyRetentionPeriod
            $DaysOfMonth            = $WebhookBodyObj.DaysOfMonth
            $VaultName              = $WebhookBodyObj.VaultName
            $AzureSubscriptionID    = $WebhookBodyObj.AzureSubscriptionID
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

    

    Inlinescript
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
            # Create Daily Retention
            $DailyRetention = New-AzureRmBackupRetentionPolicyObject `
                              -DailyRetention `
                              -Retention $Using:DailyRetentionPeriod `
                              -ErrorAction Stop
            Write-Output -InputObject 'Daily retention was created successfully.'
        }
        Catch
        {
            $ErrorMessage = 'Failed to create Daily Retention.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }

        Try
        {
            $DaysOfMonth = $Using:DaysOfMonth -replace '[()]',''
            $DaysOfMonthArray = $DaysOfMonth.Split(',')
            [Collections.Generic.List[String]]$DaysOfMonthList = $DaysOfMonthArray
            $MonthlyRetention = New-AzureRmBackupRetentionPolicyObject `
                                -MonthlyRetentionInDailyFormat `
                                -DaysOfMonth $DaysOfMonthList `
                                -Retention $Using:MonthlyRetentionPeriod `
                                -ErrorAction Stop
            Write-Output -InputObject 'Monthly retention was created successfully.'

        }
        Catch
        {
            $ErrorMessage = 'Failed to create Monthly Retention.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }

        Try
        {
            $ProtectionPolicy = New-AzureRmBackupProtectionPolicy `
                                -Name $Using:BackupPolicyName `
                                -Type AzureVM `
                                -Daily `
                                -BackupTime ([datetime]$Using:BackupTime) `
                                -RetentionPolicy ($DailyRetention,$MonthlyRetention) `
                                -Vault $Vault `
                                -ErrorAction Stop
            Write-Output -InputObject 'Backup policy was created successfully.'
    
        }
        Catch
        {
            $ErrorMessage = 'Failed to create Backup Policy.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }
    }
    


}