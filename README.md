# Check Failed Power Automate Flows Script

## Overview
This PowerShell script checks all Power Automate flows across all your environments for failures in the last 24 hours (or custom time period).

## Prerequisites

1. **PowerShell 5.1 or later** (PowerShell 7+ recommended)
2. **Power Platform Administrator access** or appropriate permissions to view flows
3. **Internet connection** to connect to Power Platform

## Installation

The script will automatically install required modules if they're missing:
- `Microsoft.PowerApps.Administration.PowerShell`
- `Microsoft.PowerApps.PowerShell`

Or you can install them manually beforehand:

```powershell
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
Install-Module -Name Microsoft.PowerApps.PowerShell -Scope CurrentUser
```

## Usage

### Basic Usage (Last 24 hours)
```powershell
.\Check-FailedFlows.ps1
```

### Custom Time Period
```powershell
# Check last 48 hours
.\Check-FailedFlows.ps1 -Hours 48

# Check last 7 days
.\Check-FailedFlows.ps1 -Hours 168
```

## What the Script Does

1. **Authenticates**: Prompts you to sign in to Power Platform
2. **Scans**: Retrieves all environments and flows you have access to
3. **Analyzes**: Checks each flow for failed runs in the specified time period
4. **Reports**: Displays:
   - Total environments checked
   - Total flows checked
   - Number of flows with failures
   - Detailed table of failed flows
5. **Exports**: Saves results to a CSV file with timestamp

## Output

### Console Output
- Summary statistics
- List of failed flows with environment and failure count
- Color-coded results (Red = failures, Green = no failures)

### CSV Export
A CSV file is automatically created in the same directory as the script:
- Filename format: `FailedFlows_YYYYMMDD_HHMMSS.csv`
- Contains: Environment, Flow Name, Failure Count, Last Failure Time

## Example Output

```
=== Power Automate Failed Flows Report ===
Checking flows from the last 24 hours

Found 3 environment(s)

Processing Environment: Production
  Found 45 flow(s)
  [FAILED] Daily Report Generator - 2 failure(s)

Processing Environment: Development
  Found 12 flow(s)

=== Summary ===
Total Environments Checked: 3
Total Flows Checked: 57
Flows with Failures (last 24 hours): 1

Results exported to: FailedFlows_20251009_143022.csv
```

## Permissions Required

You need one of the following:
- **Power Platform Administrator**
- **Dynamics 365 Administrator**
- **Environment permissions** to view flows in specific environments

## Troubleshooting

### Authentication Issues
If you get authentication errors, try:
```powershell
# Clear cached credentials
Add-PowerAppsAccount -Endpoint "prod"
```

### Module Installation Issues
Run PowerShell as Administrator and try:
```powershell
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force -AllowClobber
```

### Timeout Issues
For large environments, the script may take several minutes. This is normal.

## Notes

- The script only checks flows you have permission to view
- Shared flows and flows in other user's contexts may not appear
- The script does not modify any flows, it's read-only
- CSV files are saved in the same directory as the script

## Advanced Usage

### Running Silently (No Interaction)
For scheduled tasks, you can suppress certain outputs by redirecting:
```powershell
.\Check-FailedFlows.ps1 -Hours 24 | Out-File -FilePath "FlowReport.txt"
```

### Filtering Results
You can pipe the results through additional PowerShell filters:
```powershell
# Only show flows with more than 5 failures
.\Check-FailedFlows.ps1 | Where-Object { $_.FailureCount -gt 5 }
```
