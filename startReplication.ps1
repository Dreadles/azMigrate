param (
    [object]$curatedVmList,
    [string]$migrateSubscriptionId,
    [int]$checkJobStatusTime = 10
)

# Import Shared Functions Module
Import-Module ".\sharedFunctions.psm1" -Force

$jobName = "Start Replication"

switchSubscription -subscriptionId $migrateSubscriptionId

if ($curatedVmList.Length -ne 0) {

    switchSubscription -subscriptionId $migrateSubscriptionId
    
    ForEach ($vm in $curatedVmList) {

        Write-Host "$(get-date) - VM - $($vm.TargetVMName)" -ForegroundColor Cyan -BackgroundColor Black

        $DisksToInclude = @()
        forEach ($disk in $vm.Disks) {
            $disk = New-AzMigrateDiskMapping -DiskId $disk.DiskID -DiskType $disk.DiskType -IsOSDisk $disk.IsOsDisk

            $DisksToInclude += $disk
        }

        if (Get-AzMigrateServerReplication -DiscoveredMachineId $vm.MachineId -ErrorAction SilentlyContinue) {
            Write-Host "$(Get-Date) - VM - $($vm.TargetVMName) - is already configured for Replication. Skipping Enabling Replication" -ForegroundColor Yellow -BackgroundColor Black
        }
        Else {
            # Check to see if the OS is Windows or Linux and update the LicenseType accordingly
            if ($vm.sourceOs -match '(?i)windows') {
                if ([String]::IsNullOrEmpty($vm.LicenseType)) {
                    $licenseType = "NoLicenseType"
                }
                Else {
                    $licenseType = "WindowsServer"
                }

                try {
                    $submittedJob = New-AzMigrateServerReplication `
                        -LicenseType $licenseType `
                        -TargetResourceGroupId $vm.TargetResourceGroupId `
                        -TestNetworkId $vm.TestNetworkId `
                        -TestSubnetName $vm.TestSubnetName `
                        -TargetVMName $vm.TargetVMName `
                        -MachineId $vm.MachineId`
                        -TargetVMSize $vm.TargetVMSize `
                        -TargetNetworkId  $vm.TargetNetworkId `
                        -TargetSubnetName $vm.TargetSubnetName `
                        -PerformAutoResync true `
                        -TargetAvailabilityZone $vm.TargetAvailabilityZone `
                        -DiskToInclude $DisksToInclude
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
                    $submittedJob = New-AzMigrateServerReplication `
                        -LicenseType "NoLicenseType" `
                        -LinuxLicenseType $licenseType `
                        -TargetResourceGroupId $vm.TargetResourceGroupId `
                        -TestNetworkId $vm.TestNetworkId `
                        -TestSubnetName $vm.TestSubnetName `
                        -TargetVMName $vm.TargetVMName `
                        -MachineId $vm.MachineId`
                        -TargetVMSize $vm.TargetVMSize `
                        -TargetNetworkId  $vm.TargetNetworkId `
                        -TargetSubnetName $vm.TargetSubnetName `
                        -PerformAutoResync true `
                        -TargetAvailabilityZone $vm.TargetAvailabilityZone `
                        -DiskToInclude $DisksToInclude
                }
                catch {
                    Write-Host "$(get-date) - Error Submitting Job - $($_.Exception.Message)" -ForegroundColor Red -BackgroundColor Black
                    break
                }
            }

            Write-Host "$(get-date) - Job Submitted, now watching status for $($checkJobStatusTime) seconds" -ForegroundColor Green -BackgroundColor Black
            $submittedJob = checkJobStatus -jobId $submittedJob.Id -time $checkJobStatusTime

            reportJobStatus -job $submittedJob -jobName $jobName
        }
    }
    Write-Host "$(Get-Date) - All VMs Processed" -ForegroundColor Green -BackgroundColor Black
}
Else {
    Write-Host "$(Get-Date) - No VMs to Process" -ForegroundColor Green -BackgroundColor Black
}