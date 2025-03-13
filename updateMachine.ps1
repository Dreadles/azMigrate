
param (
    [object]$curatedVmList,
    [string]$migrateSubscriptionId,
    [string]$migrateResourceGroupName,
    [string]$migrateProjectName,
    [int]$checkJobStatusTime = 10
)

# Import Shared Functions Module
Import-Module ".\sharedFunctions.psm1" -Force

$jobName = "Update Machine"

if ($curatedVmList.Length -ne 0) {

    # Get the current context
    $currentContext = Get-AzContext

    # Check if we're already in the correct subscription
    if ($currentContext.Subscription.Id -ne $migrateSubscriptionId) {
        Write-Host "$(Get-Date) - Switching to Azure Migrate Subscription" -ForegroundColor Green -BackgroundColor Black
        Set-AzContext -SubscriptionId $migrateSubscriptionId > $null
        Start-Sleep 2
    }
    else {
        Write-Host "$(Get-Date) - Already in the correct subscription. Skipping switch." -ForegroundColor Yellow -BackgroundColor Black
    }

    foreach ($vm in $curatedVmList) {

        Write-Host "$(get-date) - VM - $($vm.TargetVMName)" -ForegroundColor Cyan -BackgroundColor Black

        $replicatedVm = Get-AzMigrateServerReplication -DiscoveredMachineId $vm.MachineId
        #$replicatedVm.ProviderSpecificDetail.VMNic[0]

        $valid = validateStates -allowedOperations $replicatedVm.AllowedOperation -processRequested @("Migrate", "PauseReplication", "ResumeReplication", "StartResync", "TestMigrate")

        if ($valid) {
            $disksToChange = @()
            forEach ($disk in $vm.Disks) {
                $disk = New-AzMigrateDiskMapping -DiskId $disk.DiskID -DiskType $disk.DiskType -IsOSDisk $disk.IsOsDisk

                $disksToChange += $disk
            }

            # Create NIC object
            $NicToUpdate = [Microsoft.Azure.PowerShell.Cmdlets.Migrate.Models.Api202401.VMwareCbtNicInput]::new()
            #$NicToUpdate1 = [Microsoft.Azure.PowerShell.Cmdlets.Migrate.Models.Api202401.VMwareCbtNicInput]::new()

            # Create a NIC Counter to ensure we can set the first NIC as Primary
            $nicCounter = 0
            $nicsToChange = @()
            foreach ($nic in $vm.Nics) {

                $NicToUpdate.NicId = $replicatedVm.ProviderSpecificDetail.VMNic[$nicCounter].NicId
                $NicToUpdate.TargetSubnetName = $vm.TargetSubnetName
                $NicToUpdate.TestSubnetName = $vm.TestSubnetName
                $NicToUpdate.TargetNicName = $replicatedVm.ProviderSpecificDetail.VMNic[$nicCounter].TargetNicName

                #$NicToUpdate1.NicId = $nic
                #$NicToUpdate1.TargetNicSubnet = $vm.TargetSubnetName
                #$NicToUpdate1.TestNicSubnet      = $vm.TestSubnetName

                # If this is the first NIC in the list, then safe to assume this will be primary.
                if ($nicCounter -eq 0) {

                    $NicToUpdate.IsPrimaryNIC = "true"
                    $NicToUpdate.IsSelectedForMigration = "true"

                    #$NicToUpdate1.TargetNicSelectionType = "primary"

                    if (![String]::IsNullOrEmpty($vm.PrimaryIPAddress)) {
                        $NicToUpdate.TargetStaticIPAddress = $vm.PrimaryIPAddress
                        #$NicToUpdate1.TargetNicIP = $vm.PrimaryIPAddress
                    }
                }
                # Any other NIC, disable for Migration
                else {
                    $NicToUpdate.IsPrimaryNIC = "false"
                    $NicToUpdate.IsSelectedForMigration = "false"

                    #$NicToUpdate1.TargetNicSelectionType = "donotcreate"
                }

                #$NicToUpdate.ToJSonString()

                $nicsToChange += $NicToUpdate
                $nicCounter++
            }

            # Check to see if the OS is Windows or Linux and update the LicenseType accordingly
            if ($vm.OperatingSystem -match '(?i)windows') {
                if ([String]::IsNullOrEmpty($vm.LicenseType)) {
                    $licenseType = "NoLicenseType"
                }
                Else {
                    $licenseType = "WindowsServer"
                }

                try {
                    $updateJob = Set-AzMigrateServerReplication `
                        -TargetObjectID $replicatedVm.id `
                        -TargetVMName $vm.TargetVMName `
                        -TargetVMSize $vm.TargetVMSize `
                        -TargetNetworkId $vm.TargetNetworkId `
                        -TestNetworkId $vm.TestNetworkId `
                        -TargetResourceGroupID $vm.TargetResourceGroupID `
                        -NicToUpdate $nicsToChange `
                        -DiskToUpdate $disksToChange `
                        -TargetAvailabilityZone $vm.TargetAvailabilityZone
                }
                catch {
                    Write-Host "$(get-date) - Error Submitting Job - $($_.Exception.Message)" -ForegroundColor Red -BackgroundColor Black
                    break
                }
            }
            Else {
                if ([String]::IsNullOrEmpty($vm.LinuxLicenseType)) {
                    $licenseType = "NoLicenseType"
                }
                Else {
                    $licenseType = "LinuxServer"
                }

                try {
                    $updateJob = Set-AzMigrateServerReplication `
                        -TargetObjectID $replicatedVm.id `
                        -TargetVMName $vm.TargetVMName `
                        -TargetVMSize $vm.TargetVMSize `
                        -TargetNetworkId $vm.TargetNetworkId `
                        -TestNetworkId $vm.TestNetworkId `
                        -TargetResourceGroupID $vm.TargetResourceGroupID `
                        -NicToUpdate $nicsToChange `
                        -DiskToUpdate $disksToChange `
                        -TargetAvailabilityZone $vm.TargetAvailabilityZone `
                        -LinuxLicenseType $licenseType
                }
                catch {
                    Write-Host "$(get-date) - Error Submitting Job - $($_.Exception.Message)" -ForegroundColor Red -BackgroundColor Black
                    break
                }
            }

            Write-Host "$(get-date) - Job Submitted, now watching status for $($checkJobStatusTime) seconds" -ForegroundColor Green -BackgroundColor Black
            $submittedJob = checkJobStatus -jobId $updateJob.Id -time $checkJobStatusTime

            reportJobStatus -job $submittedJob -jobName $jobName

        }
        else {
            Write-Host "$(get-date) - VM $($vm.TargetVMName) Machine Update Job Not Started - VM Not in a Valid State $($replicatedVm.TestMigrateState) and $($replicatedVm.MigrationState)" -ForegroundColor Red -BackgroundColor Black
        }  
    }

    Write-Host "$(Get-Date) - All VMs Processed" -ForegroundColor Green -BackgroundColor Black
}
Else {
    Write-Host "$(Get-Date) - No VMs to Process" -ForegroundColor Green -BackgroundColor Black
}

