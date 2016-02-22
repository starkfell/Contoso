<#

    .SYNOPSIS
       Restores Classic VM from Azure Backup.

    .DESCRIPTION
       Restores Classic VM from Azure Backup. The existing
       VM needs to be deleted in advance as Classic VM with
       the same name will be created in the same Cloud Service.
       It resotres the VM size, name and disks. Additional 
       settings like endpoints and static IP addresses will 
       need to be configured manually after the restore.
       Azure RM and Azure Service Management cmdlets are
       used.

    .PARAMETER  VMName
	   Mandatory parameter. This parameter is used for 
       finding the Azure VM in Backup and restore it.

    .PARAMETER  VaultName
	   Not mandatory parameter. This parameter is used for 
       finding in which Vault the VM is located. If not 
       specified value will be taken from variable in 
       Automation Asset store.

    .PARAMETER  RecoveryPointId
	   Mandatory parameter. This parameter is used from 
       which Recovery Point the VM should be restored.
       If 0 value is provided instead of 
       Recovery Point ID the runbook will restore from
       the latest succssfull backup.

    .PARAMETER  DestinationStorageAccountName
	   Mandatory parameter. This parameter is used for
       location where the VHDs and the VM configuration
       will be restored. It must be the same storage account
       where the previous VM was located.

    .PARAMETER  CloudServiceName
	   Mandatory parameter. This parameter is used for
       restoring the VM in a specific Cloud Service.
       It must be the same Cloud Service as the 
       previous VM.
       
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
workflow Restore-AzureClassicVM
{
    param (
        [Parameter(Mandatory=$true)]
        [String] 
        $VMName,

        [Parameter(Mandatory=$false)]
        [String] 
        $VaultName,

        [Parameter(Mandatory=$true)]
        [int64] 
        $RecoveryPointId,
        
        [Parameter(Mandatory=$true)]
        [String] 
        $DestinationStorageAccountName,

        [Parameter(Mandatory=$true)]
        [String] 
        $CloudServiceName,

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
            $VMName                        = $WebhookBodyObj.VMName
            $VaultName                     = $WebhookBodyObj.VaultName
            $AzureSubscriptionID           = $WebhookBodyObj.AzureSubscriptionID
            $RecoveryPointId               = $WebhookBodyObj.RecoveryPointId
            $DestinationStorageAccountName = $WebhookBodyObj.DestinationStorageAccountName
            $CloudServiceName              = $WebhookBodyObj.CloudServiceName
            $CloudServiceLocation          = $WebhookBodyObj.CloudServiceLocation
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
            # Get Backup item
            $backupitem = Get-AzureRMBackupContainer `
                          -Vault $Vault `
                          -Type AzureVM `
                          -name $Using:VMName `
                          -ErrorAction Stop | `
                          Get-AzureRMBackupItem `
                          -ErrorAction Stop
   
            If ($Using:RecoveryPointId -eq 0)
            {
                $RecoveryPoint =  Get-AzureRMBackupRecoveryPoint `
                                  -Item $backupitem `
                                  -ErrorAction Stop
                $RestorePoint = $RecoveryPoint[0]
        
            }
            Else
            {
                # Get Recovery Point
                $RecoveryPoint = Get-AzureRMBackupRecoveryPoint `
                                 -RecoveryPointId $Using:RecoveryPointId `
                                 -Item $backupitem `
                                 -ErrorAction Stop
                $RestorePoint = $RecoveryPoint 
            }
        

            # Start Restore
            $RestoreJob = Restore-AzureRMBackupItem `
                          -StorageAccountName $Using:DestinationStorageAccountName `
                          -RecoveryPoint $RestorePoint `
                          -ErrorAction Stop
            Write-Output -InputObject 'Started Restore job.'
    
        }
        Catch
        {
            $ErrorMessage = 'Failed to start restore.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }
    
        Try
        { 
            # Wait for restore job to complete
            $JobOutput = Wait-AzureRmBackupJob -Job $RestoreJob

            If ($JobOutput.Status -eq 'Completed')
                {
                    $RestoreJobDetails = Get-AzureRMBackupJobDetails `
                                         -Job $RestoreJob `
                                         -ErrorAction Stop
                    Write-Output -InputObject 'Restore job completed successful.'
                }
                Else
                {
                    $ErrorMessage = 'Restore Job is with status '
                    $ErrorMessage += $JobOutput.Status
                    $ErrorMessage += '.'
                    $ErrorMessage += " `n"
                    $ErrorMessage += 'Restore Job Error Details: '
                    $ErrorMessage += $JobOutput.ErrorDetails
                    Write-Error -Message $ErrorMessage `
                                -ErrorAction Stop
                }
        }
        Catch
        {
            $ErrorMessage = 'Failed to get restore job.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }
    
        # Get Restore job data
        $properties         = $RestoreJobDetails.Properties
        $storageAccountName = $properties['Target Storage Account Name']
        $containerName      = $properties['Config Blob Container Name']
        $blobName           = $properties['Config Blob Name']

        Try
        {
            # Login to Azure Service Management
            $AzureAccount = Add-AzureAccount `
                            -Credential $Using:AzureCreds
            $SelectedSub = Select-AzureSubscription `
                           -SubscriptionId $Using:AzureSubscriptionID
            $SetStorageAccount = Set-AzureSubscription `
                                 -SubscriptionId $Using:AzureSubscriptionID `
                                 -CurrentStorageAccountName $Using:DestinationStorageAccountName
            Write-Output -InputObject 'Successfully connected to Azure Service Management.'
        }
        Catch
        {
            $ErrorMessage = 'Failed to login to Azure Service Management.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }
        Try
        {
            $keys = Get-AzureStorageKey `
                    -StorageAccountName $storageAccountName `
                    -ErrorAction Stop
            $storageAccountKey = $keys.Primary
        
            $storageContext = New-AzureStorageContext `
                              -StorageAccountName $storageAccountName `
                              -StorageAccountKey $storageAccountKey `
                              -ErrorAction Stop

            # Create Temporary file
            $destination_path = [System.IO.Path]::GetTempFileName()
            # Download configuration
            $DownloadedFile = Get-AzureStorageBlobContent `
                              -Container $containerName `
                              -Blob $blobName `
                              -Destination $destination_path `
                              -Context $storageContext `
                              -Force `
                              -ErrorAction Stop

            # Get XML data
            $obj = [xml]((get-content $destination_path ) -replace "`0", "")
            $pvr = $obj.PersistentVMRole
            $os  = $pvr.OSVirtualHardDisk
            $dds = $pvr.DataVirtualHardDisks
            Write-Output -InputObject 'VM Configuration was successfully pulled.'
        }
        Catch
        {
            $ErrorMessage = 'Failed to get VM configuration.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }
    
        Try
        {
            # Add OS Disk
            $OSDiskName = $pvr.RoleName + 'OSDisk'
            $osDisk = Add-AzureDisk `
                      -MediaLocation $os.MediaLink `
                      -OS $os.OS `
                      -DiskName $OSDiskName `
                      -ErrorAction Stop
            Write-Output -InputObject 'Successfully created VM OS Disk.'
        }
        Catch
        {
            $ErrorMessage = 'Failed to create OS disk.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }
    
        Try
        {
            # Create VM Configuration
            $vm = New-AzureVMConfig `
                  -Name $pvr.RoleName `
                  -InstanceSize $pvr.RoleSize `
                  -DiskName $osDisk.DiskName `
                  -ErrorAction Stop
            Write-Output -InputObject 'Successfully created VM configuration.'
        }
        Catch
        {
            $ErrorMessage = 'Failed to create VM Configuration.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }
    
        Try
        {
            $DataDiskName = $pvr.RoleName + 'DataDisk'
            if (!($dds -eq $null))
            {
                foreach($d in $dds.DataVirtualHardDisk)
                {
                    $lun = 0;
                    if(!($d.Lun -eq $null))
                    {
                        $lun = $d.Lun
                    }
                    $name = $DataDiskName + $lun
                    $AddedDisk = Add-AzureDisk `
                                 -DiskName $name `
                                 -MediaLocation $d.MediaLink `
                                 -ErrorAction Stop
        
                $VMDataDisk = $vm | Add-AzureDataDisk `
                                    -Import `
                                    -DiskName $name `
                                    -LUN $lun `
                                    -ErrorAction Stop
                }
                Write-Output -InputObject 'Successfully created VM Data Disk/s.'
            }
        }
        Catch
        {
            $ErrorMessage = 'Failed to add Data Disk.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }
    
        Try
        {
            $CloudService = Get-AzureService `
                            -ServiceName $Using:CloudServiceName
            $NewVM = New-AzureVM `
                     -ServiceName $Using:CloudServiceName `
                     -Location $Using:CloudService.Location `
                     -VM $vm  `
                     -ErrorAction Stop `
                     -WarningAction SilentlyContinue
            Write-Output -InputObject 'Successfully restored VM. VM is now booting.'
        }
        Catch
        {
            $ErrorMessage = 'Failed to create VM from restored disks and configuration.'
            $ErrorMessage += " `n"
            $ErrorMessage += 'Error: '
            $ErrorMessage += $_
            Write-Error -Message $ErrorMessage `
                        -ErrorAction Stop
        }
    }
    
}