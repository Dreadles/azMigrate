function switchSubscription {
    param (
        $subscriptionId
    )

    # Get the current context
    $currentContext = Get-AzContext

    # Check if we're already in the correct subscription
    if ($currentContext.Subscription.Id -ne $subscriptionId) {
        Write-Host "$(Get-Date) - Switching to Subscription $($subscriptionId)" -ForegroundColor Green -BackgroundColor Black
        Set-AzContext -SubscriptionId $subscriptionId > $null
        Start-Sleep 2
    }
    else {
        #Write-Host "$(Get-Date) - Already in the correct subscription - $($currentContext.Subscription.Id). Skipping switch." -ForegroundColor Yellow -BackgroundColor Black
    }
}

function checkJobStatus() {
    [CmdletBinding()]
    param (
        [string]$jobId,
        [int]$time
    )

    for ($int = 0; $int -lt $time; $int++) {
        $status = (Get-AzMigrateJob -JobID $jobId).State

        If ($status -eq "Succeeded" -or $status -eq "Failed") {
            break
        }

        start-sleep 1
    }
    
    return (Get-AzMigrateJob -JobID $jobId)
}

function reportJobStatus() {
    [CmdletBinding()]
    param (
        $job,
        $jobName
    )

    if ($job.State -eq "Succeeded") {
        Write-Host "$(get-date) - $($jobName) Job Completed" -ForegroundColor Green -BackgroundColor Black
    }
    elseif ($job.State -eq "InProgress" -or $job.State -eq "NotStarted") {
        Write-Host "$(get-date) - $($jobName) Job Created, but not Started or In-Progress - $($job.Name)" -ForegroundColor Green -BackgroundColor Black
    }
    elseif ($job.State -eq "Failed") {
        Write-Host "$(get-date) - $($jobName) Job Failed" -ForegroundColor Red -BackgroundColor Black

        ForEach ($problem in $job.Error) {
            Write-Host "$(get-date) - $($problem.ErrorLevel).
            $($problem.ProviderErrorDetailErrorMessage)
            $($problem.ProviderErrorDetailPossibleCaus)
            $($problem.ProviderErrorDetailRecommendedAction)
            $($problem.ServiceErrorDetailMessage)
            $($problem.ServiceErrorDetailPossibleCaus)
            $($problem.ServiceErrorDetailRecommendedAction)"  -ForegroundColor Red -BackgroundColor Black
        }
    }  
}

function validateStates {
    [CmdletBinding()]
    param (
        $allowedOperations,
        [string[]]$processRequested
    )

    $valid = $false

    # iterate through all allowed operations from Azure Migrate, convert to string and compare against our desired action - break if true and set as valid
    foreach ($operation in $allowedOperations) {
        if ($processRequested -contains $operation.ToString()) {
            $valid = $true
            break
        }
    }

    return $valid
}