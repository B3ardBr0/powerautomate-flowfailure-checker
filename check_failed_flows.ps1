<#
.SYNOPSIS
    Checks for failed Power Automate flows across all environments in the last 24 hours.

.DESCRIPTION
    This script connects to Power Platform and retrieves all flows across all environments
    that have failed in the specified time window. It requires Power Platform Administrator
    permissions and the Microsoft.PowerApps.Administration.PowerShell module.

    By default, uses Get-AdminFlow to scan all environments as an administrator.
    Optionally, can also include user-owned flows via Get-Flow to catch any flows
    not visible through admin cmdlets.

.PARAMETER Hours
    Number of hours to look back for failed runs (default: 24)

.PARAMETER IncludeUserFlows
    When specified, also checks flows you own or have access to via Get-Flow.
    This can help catch flows in the default environment that may not appear
    in Get-AdminFlow results. Duplicates are automatically skipped.

.EXAMPLE
    .\check_failed_flows.ps1
    Checks for flows that failed in the last 24 hours across all environments

.EXAMPLE
    .\check_failed_flows.ps1 -Hours 720
    Checks for flows that failed in the last 30 days (720 hours) across all environments

.EXAMPLE
    .\check_failed_flows.ps1 -IncludeUserFlows
    Checks admin flows across all environments AND user-owned flows

.NOTES
    Requires: Microsoft.PowerApps.Administration.PowerShell and Microsoft.PowerApps.PowerShell modules
    Install with:
        Install-Module -Name Microsoft.PowerApps.Administration.PowerShell
        Install-Module -Name Microsoft.PowerApps.PowerShell

    Permissions: Power Platform Administrator or Dynamics 365 Administrator role required

    Note: If you're missing flows from your default environment, try using -IncludeUserFlows
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$Hours = 24,

    [Parameter(Mandatory=$false)]
    [switch]$IncludeUserFlows = $false
)

# Function to check and install required modules
function Install-RequiredModules {
    $requiredModules = @(
        'Microsoft.PowerApps.Administration.PowerShell',
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

# Get all environments
Write-Host "Retrieving all environments..." -ForegroundColor Yellow
try {
    $environments = Get-AdminPowerAppEnvironment
    Write-Host "Found $($environments.Count) environment(s)" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Error "Failed to retrieve environments. Error: $_"
    exit 1
}

# Initialize counters
$totalEnvironments = $environments.Count
$totalFlows = 0
$totalFailedFlows = 0
$failedFlowDetails = @()
$processedEnvironments = 0

# Iterate through each environment
foreach ($environment in $environments) {
    $processedEnvironments++
    Write-Host "[$processedEnvironments/$totalEnvironments] Processing Environment: $($environment.DisplayName)" -ForegroundColor Cyan

    try {
        # Get all flows in this environment
        $flows = Get-AdminFlow -EnvironmentName $environment.EnvironmentName

        if ($flows) {
            $envFlowCount = $flows.Count
            $totalFlows += $envFlowCount
            Write-Host "  Found $envFlowCount flow(s) in this environment" -ForegroundColor Gray

            $processedFlows = 0

            # Check each flow for failures
            foreach ($flow in $flows) {
                $processedFlows++
                Write-Host "  [$processedFlows/$envFlowCount] Checking: $($flow.DisplayName)" -ForegroundColor Gray

                try {
                    # Get flow runs
                    $runs = Get-AdminFlowRunHistory -EnvironmentName $environment.EnvironmentName -FlowName $flow.FlowName

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
                                Environment = $environment.DisplayName
                                EnvironmentID = $environment.EnvironmentName
                                FlowName = $flow.DisplayName
                                FlowID = $flow.FlowName
                                Enabled = $flow.Enabled
                                FailureCount = $failedRuns.Count
                                LastFailure = $lastFailureTime
                            }

                            Write-Host "    [FAILED] $($failedRuns.Count) failure(s) - Last: $lastFailureTime" -ForegroundColor Red
                        }
                    }
                }
                catch {
                    Write-Warning "    Could not retrieve runs for flow: $($flow.DisplayName). Error: $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Host "  No flows found in this environment" -ForegroundColor Gray
        }
    }
    catch {
        Write-Warning "  Could not retrieve flows for environment: $($environment.DisplayName). Error: $($_.Exception.Message)"
    }

    Write-Host ""
}

# Optionally check user-owned flows (to catch flows not visible via Get-AdminFlow)
if ($IncludeUserFlows) {
    Write-Host "=== Checking User-Owned Flows ===" -ForegroundColor Cyan
    Write-Host "Retrieving flows you own or have access to..." -ForegroundColor Yellow

    try {
        $userFlows = Get-Flow

        if ($userFlows) {
            Write-Host "Found $($userFlows.Count) user flow(s)" -ForegroundColor Green
            $processedUserFlows = 0

            foreach ($flow in $userFlows) {
                $processedUserFlows++
                Write-Host "[$processedUserFlows/$($userFlows.Count)] Checking: $($flow.DisplayName)" -ForegroundColor Gray

                # Skip if already processed via admin check
                $alreadyProcessed = $failedFlowDetails | Where-Object { $_.FlowID -eq $flow.FlowName }
                if ($alreadyProcessed) {
                    Write-Host "  [SKIPPED] Already checked via admin flow" -ForegroundColor DarkGray
                    continue
                }

                try {
                    # Get flow runs
                    $runs = Get-FlowRun -FlowName $flow.FlowName

                    if ($runs) {
                        # Filter for failed runs in the time window
                        $failedRuns = $runs | Where-Object {
                            $_.Status -eq 'Failed' -and
                            [DateTime]$_.StartTime -gt $timeThreshold
                        }

                        if ($failedRuns.Count -gt 0) {
                            $totalFailedFlows++
                            $totalFlows++

                            $lastFailureTime = ($failedRuns | Sort-Object StartTime -Descending | Select-Object -First 1).StartTime

                            $failedFlowDetails += [PSCustomObject]@{
                                Environment = "(User Flow)"
                                EnvironmentID = "N/A"
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
                    Write-Warning "  Could not retrieve runs for flow: $($flow.DisplayName). Error: $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Host "No user flows found" -ForegroundColor Gray
        }
    }
    catch {
        Write-Warning "Failed to retrieve user flows. Error: $($_.Exception.Message)"
    }

    Write-Host ""
}

Write-Host ""

# Display summary
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Total Environments Checked: $totalEnvironments" -ForegroundColor White
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
