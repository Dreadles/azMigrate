param (
    [object]$curatedVmList,
    [string]$migrateSubscriptionId,
    [string]$migrateResourceGroupName,
    [string]$migrateProjectName,
    [int]$checkJobStatusTime = 10
)

# Import Shared Functions Module
Import-Module ".\sharedFunctions.psm1" -Force

$jobName = "Start Test Failover"

if ($curatedVmList.Length -ne 0) {

    switchSubscription -subscriptionId $migrateSubscriptionId

    foreach ($vm in $curatedVmList) {
        Write-Host "$(get-date) - VM - $($vm.TargetVMName)" -ForegroundColor Cyan -BackgroundColor Black

        try {
            $replicatedVm = Get-AzMigrateServerReplication -DiscoveredMachineId $vm.MachineId
        }
        catch {
            Write-Host "$(get-date) - Error Retrieving Replicated Server - $($_.Exception.Message)" -ForegroundColor Red -BackgroundColor Black
            break
        }
        
        $valid = validateStates -allowedOperations $replicatedVm.AllowedOperation -processRequested @("TestMigrate")

        if ($valid) {

            try {
                $submittedJob = Start-AzMigrateTestMigration `
                    -TargetObjectID $replicatedVm.id `
                    -TestNetworkId $vm.TestNetworkId
            }
            catch {
                Write-Host "$(get-date) - Error Submitting Job - $($_.Exception.Message)" -ForegroundColor Red -BackgroundColor Black
                break
            }

            Write-Host "$(get-date) - Job Submitted, now watching status for $($checkJobStatusTime) seconds" -ForegroundColor Green -BackgroundColor Black
            $submittedJob = checkJobStatus -jobId $submittedJob.Id -time $checkJobStatusTime
    
            reportJobStatus -job $submittedJob -jobName $jobName
        }
        else {
            Write-Host "$(get-date) - VM $($vm.TargetVMName) Start Test Failover Job Not Created - VM Not in a Valid State $($replicatedVm.TestMigrateState) and $($replicatedVm.MigrationState) and $($replicatedVm.replicationStatus)" -ForegroundColor Red -BackgroundColor Black
        }  
    }

    Write-Host "$(Get-Date) - All VMs Processed" -ForegroundColor Green -BackgroundColor Black
}
Else {
    Write-Host "$(Get-Date) - No VMs to Process" -ForegroundColor Green -BackgroundColor Black
}