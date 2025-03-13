# Azure Migrate - IaaS Large Scale Migration Tooling
Powershell Tooling to assist with large-scale Azure Migrate IaaS Re-Hosts.

## Logic
Ingests a CSV file with details of a Discovered VMware / Hyper-V Virtual Machine from Azure Migrate.
The CSV File contains information specific to Replication, Test Failover, and Migration.

This code can be used to initially create a Replicated Virtual Machine, Update the Virtual Machine data once in-sync, Perform and Clean a Test Failover, Perform a cutover Migration, and Stop/Clean up the Replication Data.

Performs logging and error checking.

Example CSV file witin example directory.

## Usage
Example .\main.ps1 -vmCSV ".\wave1\application1.csv" -StartReplication

### Parameters
    [string]$vmCSV = Path to the CSV File
    [string]$migrateSubscriptionId = Subscription ID of the Azure Migrate Project
    [string]$migrateResourceGroupName = Resource Group Name of the Azure Migrate Project
    [string]$migrateProjectName = Project Name of the Azure Migrate Project
    [switch]PROCESSSWITCH - See below

### Process Switches
    [switch]$StartReplication = Starts (Enabled Replication)
    [switch]$StopReplication = Stops Replication
    [switch]$StartTestFailover = Starts Test Failover
    [switch]$StopTestFailover = Stops and Cleans Test Failover
    [switch]$StartMigration = Starts Cutover Migration (including Power down)
    [switch]$UpdateMachine = Updates the Replicated (and in Delta-Sync) Virtual Machine with data (and changes) in the CSV File. For example, the Target IP Address
    [switch]$ResumeReplication = Resumes Replication following either a Migration or Pause.