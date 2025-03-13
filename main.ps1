param (
    [string]$vmCSV,
    [string]$migrateSubscriptionId,
    [string]$migrateResourceGroupName,
    [string]$migrateProjectName,
    [switch]$StartReplication,
    [switch]$StopReplication,
    [switch]$StartTestFailover,
    [switch]$StopTestFailover,
    [switch]$StartMigration,
    [switch]$UpdateMachine,
    [switch]$ResumeReplication
)

## Logging Setup
$timeStamp = (Get-Date -Format 'yyyy-MM-dd_HHmmss')
$logPath = Join-Path -Path "$(Split-Path -Path $vmCSV)\Logs" -ChildPath "$([System.IO.Path]::GetFileNameWithoutExtension((Split-Path -Path $vmCSV -Leaf)))-$($timeStamp).txt"

# Check if the log directory exists, if not, create it
if (!(Test-Path -Path "$(Split-Path -Path $vmCSV)\Logs")) {
    New-Item -Path "$(Split-Path -Path $vmCSV)\Logs" -ItemType Directory | Out-Null
}

# Check if the log file exists, if not, create it
if (!(Test-Path -Path $logPath)) {
    New-Item -Path $logPath -ItemType File | Out-Null
}

Start-Transcript -Path $logPath -Append

# Import Shared Functions Module
Import-Module ".\sharedFunctions.psm1" -Force

# Check if the CSV file exists
if (-Not (Test-Path -Path $vmCSV)) {
    Write-Host "$(get-date) - CSV file not found at path: $CsvFilePath" -ForegroundColor Red
    exit
}

Write-Host "$(get-date) - Setting Subscription Context to Azure Migrate Subscription" -ForegroundColor Green
switchSubscription($migrateSubscriptionId)

# Import the CSV file into a variable
$csvVMList = Import-Csv -Path $vmCSV
$joinedVMDetails = @{}
$curatedVmList = @()

Write-Host "$(get-date) - Retrieving VM Details from Azure Migrate Discovered Servers. Servers in list: $($csvVMList.Length)" -ForegroundColor Cyan

# Get MachineIDs of all Servers
ForEach ($vm in $csvVMList) {

    Write-Host "$(get-date) - Looking for Discovered Server - $($vm.vmName)" -ForegroundColor Cyan

    if ($vm.type -ne "VM") {
        Write-Host "$(get-date) - $($vm.vmName) - Resource in CSV File is not a Virtual Machine. Skipping" -ForegroundColor Red
        break
    }

    $azMigrateDiscoveredServer = Get-AzMigrateDiscoveredServer -ResourceGroupName $migrateResourceGroupName -ProjectName $migrateProjectName | Where-Object { $_.DisplayName -eq $vm.vmName }

    if ([String]::IsNullOrEmpty($azMigrateDiscoveredServer.id)) {
        Write-Host "$(get-date) - $($vm.vmName) - VM Could not be found. Skipping" -ForegroundColor Red
        break
    }

    if ($azMigrateDiscoveredServer.MaxSnapshot -ne -1 -and $azMigrateDiscoveredServer.Type -eq "Microsoft.OffAzure/VMWareSites/Machines") {
        Write-Host "$(get-date) - $($vm.vmName) - VMware Machine has an active Snapshot - Skipping" -ForegroundColor Red
        break
    }

    # Join the CSV and Discovered Server details together for further processing.
    $joinedVMObject = [PSCustomObject]@{
        csv       = $vm
        azMigrate = $azMigrateDiscoveredServer
    }

    $joinedVMDetails[$vm.vmName] = $joinedVMObject
}

Write-Host "$(get-date) - Finished retrieving Discovered Servers from Azure Migration. Total Valid Discovered Servers: $($joinedVMDetails.Count)" -ForegroundColor Cyan

ForEach ($vmName in $joinedVMDetails.Keys) {

    # Grab the complete VM details Object - discovered server details from AzMigrate and CSV File Details
    $vmObject = $joinedVMDetails[$vmName]

    # Check to see if operation requires gathering details about the VM to increase speed. Start Replication or Update Machine requires details about the VM. If not, just return object with machineId
    if ($StartReplication -or $UpdateMachine -or $StartTestFailover) {

        switchSubscription($vmObject.csv.targetSubscriptionId)
        
        $disksToAdd = @()
        # Grab the OS Disk Uuid - fail if not found
        $osDiskId = ($vmObject.azMigrate.Disk | Where-Object { $_.name -eq $vmObject.csv.osDiskName }).Uuid
        if ([String]::IsNullOrEmpty($osDiskId)) {
            Write-Host "$(get-date) - $($vmObject.csv.vmName) - Could not find OS disk name $($vmObject.csv.osDiskName). Skipping" -ForegroundColor Red
            break
        }
        Else {
            # Add the disk to the disksToAdd Object - but specify osdisk
            $diskObject = [PSCustomObject]@{
                DiskId   = $osDiskId
                DiskType = $vmObject.csv.diskSku
                IsOsDisk = $true
            }
    
            $disksToAdd += $diskObject
        }
    
        # Grab data disk Uuids
        foreach ($dataDisk in ($vmObject.azMigrate.Disk | Where-Object { $_.name -ne $vmObject.csv.osDiskName })) {
            # Add the disk to the disksToAdd Object - but specify osdisk false for data disks
            $diskObject = [PSCustomObject]@{
                DiskId   = $dataDisk.Uuid
                DiskType = $vmObject.csv.diskSku
                IsOsDisk = $false
            }
    
            $disksToAdd += $diskObject
        }
    
        # Grab Nic Uuids
        $nics = @()
        foreach ($nic in ($vmObject.azMigrate.NetworkAdapter)) {
            $nics += $nic.NicId
        }
    
        # Resource Group Details
        $targetResourceGroupId = (Get-AzResourceGroup -name $vmObject.csv.targetResourceGroup).ResourceId
        if ([String]::IsNullOrEmpty($targetResourceGroupId)) {
            Write-Host "$(get-date) - $($vmObject.csv.vmName) - Could not find Target Resource Group $($vmObject.csv.targetResourceGroup). Skipping" -ForegroundColor Red
            break
        }
    
        # Vnet Details
        $targetNetworkId = (Get-AzVirtualNetwork -name $vmObject.csv.targetNetworkName).id
        if ([String]::IsNullOrEmpty($targetNetworkId)) {
            Write-Host "$(get-date) - $($vmObject.csv.vmName) - Could not find Target Vnet $($vmObject.csv.targetNetworkName). Skipping" -ForegroundColor Red
            break
        }
    
        # Test Vnet Details
        $testNetworkId = (Get-AzVirtualNetwork -name $vmObject.csv.testNetworkName).id
        if ([String]::IsNullOrEmpty($testNetworkId)) {
            Write-Host "$(get-date) - $($vmObject.csv.vmName) - Could not find Test Vnet $($vmObject.csv.testNetworkName). Skipping" -ForegroundColor Red
            break
        }
    
        $vmObject = [PSCustomObject]@{
            TargetVMName           = $vmObject.csv.targetVmName
            TargetResourceGroupId  = $targetResourceGroupId
            TargetVMSize           = $vmObject.csv.targetSkuSize
            MachineId              = $vmObject.azMigrate.id
            WindowsLicenseType     = $vmObject.csv.windowslicenseType
            LinuxLicenseType       = $vmObject.csv.linuxLicenseType
            OperatingSystem        = $vmObject.azMigrate.OperatingSystemDetailOSName
            OSDiskID               = $osDiskId
            Disks                  = $disksToAdd
            Nics                   = $nics
            PrimaryIPAddress       = $vmObject.csv.primaryIPAddress
            TargetNetworkId        = $targetNetworkId
            TargetSubnetName       = $vmObject.csv.targetSubnetName
            TestNetworkId          = $testNetworkId
            TestSubnetName         = $vmObject.csv.testSubnetName
            TargetAvailabilityZone = $vmObject.csv.targetAvailabilityZone
        }
    }
    Else {

        $vmObject = [PSCustomObject]@{
            TargetVMName = $vmObject.csv.targetVmName
            MachineId    = $vmObject.azMigrate.id
        }
    }


    $curatedVmList += $vmObject
}

# Run the specified task based on the switch
if ($StartReplication) {
    Write-Host "$(get-date) - Starting Replication for validated Virtual Machines" -ForegroundColor Cyan -BackgroundColor Black
    .\StartReplication.ps1 -curatedVmList $curatedVmList -migrateSubscriptionId $migrateSubscriptionId
}

if ($UpdateMachine) {
    Write-Host "$(get-date) - Updating Replicated Virtual Machine Properties for validated Virtual Machines" -ForegroundColor Cyan -BackgroundColor Black
    .\updateMachine.ps1 -curatedVmList $curatedVmList -migrateSubscriptionId $migrateSubscriptionId -migrateProjectName $migrateProjectName -migrateResourceGroupName $migrateResourceGroupName
}

if ($StartTestFailover) {
    Write-Host "$(get-date) - Starting Test Failover for validated Virtual Machines" -ForegroundColor Cyan -BackgroundColor Black
    .\StartTestFailover.ps1 -curatedVmList $curatedVmList -migrateSubscriptionId $migrateSubscriptionId -migrateProjectName $migrateProjectName -migrateResourceGroupName $migrateResourceGroupName
}

if ($StopTestFailover) {
    Write-Host "$(get-date) - Starting Test Failover Clean-up for validated Virtual Machines" -ForegroundColor Cyan -BackgroundColor Black
    .\StopTestFailover.ps1 -curatedVmList $curatedVmList -migrateSubscriptionId $migrateSubscriptionId -migrateProjectName $migrateProjectName -migrateResourceGroupName $migrateResourceGroupName
}

if ($StartMigration) {
    Write-Host "Proceed with Migration of $($joinedVMDetails.Count) Servers. SOURCE MACHINES WILL BE SHUT DOWN? (Y/N)"  -ForegroundColor Magenta -BackgroundColor Black
    $answer = Read-Host
    if ($answer -eq 'Y' -or $answer -eq 'y') {
        Write-Host "$(get-date) - Starting Migration Cutover for validated Virtual Machines" -ForegroundColor Cyan -BackgroundColor Black
        .\startMigration.ps1 -curatedVmList $curatedVmList -migrateSubscriptionId $migrateSubscriptionId -migrateProjectName $migrateProjectName -migrateResourceGroupName $migrateResourceGroupName
    }
    elseif ($answer -eq 'N' -or $answer -eq 'n') {
        Write-Host "$(get-date) - Cancelling Migration" -ForegroundColor Cyan -BackgroundColor Black
        break
    }
    else {
        Write-Output "Invalid selection. Please enter Y or N."
    }

}

if ($StopReplication) {
    Write-Host "$(get-date) - Stopping Replication for validated Virtual Machines" -ForegroundColor Cyan -BackgroundColor Black
    .\stopReplication.ps1 -curatedVmList $curatedVmList -migrateSubscriptionId $migrateSubscriptionId -migrateProjectName $migrateProjectName -migrateResourceGroupName $migrateResourceGroupName
}

if ($ResumeReplication) {
    Write-Host "$(get-date) - Resuming Replication for validated Virtual Machines" -ForegroundColor Cyan -BackgroundColor Black
    .\resumeReplication.ps1 -curatedVmList $curatedVmList -migrateSubscriptionId $migrateSubscriptionId -migrateProjectName $migrateProjectName -migrateResourceGroupName $migrateResourceGroupName
}

Stop-Transcript