<#
.SYNOPSIS
    Checks for failed Power Automate flows in the last 24 hours.

.DESCRIPTION
    This script connects to Power Platform and retrieves all flows you own
    that have failed in the last 24 hours. It requires the Microsoft.PowerApps.PowerShell
    module to be installed.

    Features:
    - Progress bar showing real-time check status
    - Automatic retry logic for transient API failures (3 retries with exponential backoff)
    - CSV export of failed flows with timestamps
    - Color-coded console output

.PARAMETER Hours
    Number of hours to look back for failed runs (default: 24)

.EXAMPLE
    .\check_failed_flows.ps1
    Checks for flows that failed in the last 24 hours

.EXAMPLE
    .\check_failed_flows.ps1 -Hours 720
    Checks for flows that failed in the last 30 days (720 hours)

.NOTES
    Requires: Microsoft.PowerApps.PowerShell module
    Install with: Install-Module -Name Microsoft.PowerApps.PowerShell

    Retry Logic: API calls will automatically retry up to 3 times with
    exponential backoff (2s, 4s, 8s) to handle transient failures.
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$Hours = 24
)

# Function to retry API calls with exponential backoff
function Invoke-WithRetry {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory=$false)]
        [int]$InitialDelaySeconds = 2
    )

    $attempt = 0
    $delay = $InitialDelaySeconds

    while ($attempt -lt $MaxRetries) {
        try {
            return & $ScriptBlock
        }
        catch {
            $attempt++
            if ($attempt -ge $MaxRetries) {
                throw
            }

            Write-Warning "API call failed (attempt $attempt/$MaxRetries). Retrying in $delay seconds... Error: $($_.Exception.Message)"
            Start-Sleep -Seconds $delay
            $delay = $delay * 2  # Exponential backoff
        }
    }
}

# Function to check and install required modules
function Install-RequiredModules {
    $requiredModules = @(
        'Microsoft.PowerApps.PowerShell'
    )

    foreach ($module in $requiredModules) {
        if (!(Get-Module -ListAvailable -Name $module)) {
            Write-Host "Installing module: $module" -ForegroundColor Yellow
            try {
                Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
                Write-Host "Successfully installed $module" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to install $module. Error: $_"
                return $false
            }
        }

        # Import the module
        Import-Module $module -ErrorAction Stop
    }
    return $true
}

# Main script execution
Write-Host "=== Power Automate Failed Flows Report ===" -ForegroundColor Cyan
Write-Host "Checking flows from the last $Hours hours" -ForegroundColor Cyan
Write-Host ""

# Check and install required modules
Write-Host "Checking required PowerShell modules..." -ForegroundColor Yellow
if (!(Install-RequiredModules)) {
    Write-Error "Failed to install required modules. Exiting."
    exit 1
}

# Connect to Power Platform
Write-Host "Connecting to Power Platform..." -ForegroundColor Yellow
try {
    Add-PowerAppsAccount
}
catch {
    Write-Error "Failed to connect to Power Platform. Error: $_"
    exit 1
}

# Calculate the time threshold
$timeThreshold = (Get-Date).AddHours(-$Hours)
Write-Host "Looking for failures since: $($timeThreshold.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
Write-Host ""

# Get all flows with retry logic
Write-Host "Retrieving all flows..." -ForegroundColor Yellow
try {
    $flows = Invoke-WithRetry -ScriptBlock { Get-Flow }
    Write-Host "Found $($flows.Count) flow(s)" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Error "Failed to retrieve flows after multiple retries. Error: $_"
    exit 1
}

# Initialize counters
$totalFlows = $flows.Count
$totalFailedFlows = 0
$failedFlowDetails = @()
$processedFlows = 0

# Check each flow for failures
foreach ($flow in $flows) {
    $processedFlows++
    $percentComplete = [math]::Round(($processedFlows / $totalFlows) * 100)

    # Update progress bar
    Write-Progress -Activity "Checking Power Automate Flows for Failures" `
                   -Status "Processing: $($flow.DisplayName)" `
                   -PercentComplete $percentComplete `
                   -CurrentOperation "Flow $processedFlows of $totalFlows"

    Write-Host "[$processedFlows/$totalFlows] Checking: $($flow.DisplayName)" -ForegroundColor Gray

    try {
        # Get flow runs with retry logic
        $runs = Invoke-WithRetry -ScriptBlock {
            Get-FlowRun -FlowName $flow.FlowName
        }

        if ($runs) {
            # Filter for failed runs in the time window
            $failedRuns = $runs | Where-Object {
                $_.Status -eq 'Failed' -and
                [DateTime]$_.StartTime -gt $timeThreshold
            }

            if ($failedRuns.Count -gt 0) {
                $totalFailedFlows++

                $lastFailureTime = ($failedRuns | Sort-Object StartTime -Descending | Select-Object -First 1).StartTime

                $failedFlowDetails += [PSCustomObject]@{
                    FlowName = $flow.DisplayName
                    FlowID = $flow.FlowName
                    Enabled = $flow.Enabled
                    FailureCount = $failedRuns.Count
                    LastFailure = $lastFailureTime
                }

                Write-Host "  [FAILED] $($failedRuns.Count) failure(s) - Last: $lastFailureTime" -ForegroundColor Red
            }
        }
    }
    catch {
        Write-Warning "  Could not retrieve runs for flow: $($flow.DisplayName) after retries. Error: $($_.Exception.Message)"
    }
}

# Clear progress bar
Write-Progress -Activity "Checking Power Automate Flows for Failures" -Completed

Write-Host ""

# Display summary
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Total Flows Checked: $totalFlows" -ForegroundColor White
Write-Host "Flows with Failures (last $Hours hours): $totalFailedFlows" -ForegroundColor $(if ($totalFailedFlows -gt 0) { 'Red' } else { 'Green' })
Write-Host ""

# Display detailed results
if ($failedFlowDetails.Count -gt 0) {
    Write-Host "=== Failed Flows Details ===" -ForegroundColor Red
    $failedFlowDetails | Sort-Object FailureCount -Descending | Format-Table -AutoSize

    # Export to CSV
    $csvPath = Join-Path $PSScriptRoot "FailedFlows_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $failedFlowDetails | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "Results exported to: $csvPath" -ForegroundColor Green
}
else {
    Write-Host "No failed flows found in the last $Hours hours!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Script completed." -ForegroundColor Cyan
