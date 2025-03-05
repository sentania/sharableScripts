# PowerShell script to check a Windows service status, logging results and returning the percentage of successful checks
param (
    [string]$serviceName,
    [int]$loopCount
)

# Set the maximum allowed execution time (in seconds)
$maxExecutionTime = 285  # 4 minutes and 45 seconds

# Ensure at least 4 loops, or as many as requested, whichever is higher
$actualLoops = [math]::Max($loopCount, 4)

# Sanitize the service name to create a filesystem-safe log file name
$safeServiceName = ($serviceName -replace '[^a-zA-Z0-9]', '_')
$logFilePath = "C:\temp\$safeServiceName-monitor.log"

# Initialize the log file, clearing it if it exceeds 5 MB at the start
if (Test-Path $logFilePath) {
    $fileInfo = Get-Item $logFilePath
    if ($fileInfo.Length -gt 5242880) {
        Clear-Content $logFilePath
    }
} else {
    # Create the directory if it does not exist
    New-Item -ItemType Directory -Force -Path (Split-Path $logFilePath)
}

# Function to log each entry with a timestamp
function Log-Entry {
    param (
        [string]$message
    )

    # Append the log entry with a timestamp
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$timestamp - $message" | Out-File -FilePath $logFilePath -Append
}

# Initialize variables for tracking success count
$successCount = 0

# Calculate the sleep interval, capped at a maximum of 60 seconds
$sleepInterval = [math]::Min(($maxExecutionTime - ($actualLoops * 15)) / $actualLoops, 60)

# Loop to check the service status
for ($i = 0; $i -lt $actualLoops; $i++) {
    try {
        # Check the status of the specified service
        $service = Get-Service -Name $serviceName -ErrorAction Stop

        # Determine success based on whether the service is running
        $status = if ($service.Status -eq 'Running') { 1 } else { 0 }
    } catch {
        # If there's an error (e.g., service not found), set status to 0 (fail)
        $status = 0
    }

    # Increment success count if status is successful
    if ($status -eq 1) {
        $successCount++
    }

    # Log the result for this loop iteration
    Log-Entry "$serviceName - Loop $($i + 1) - Status: $status"

    # Pause for the dynamically calculated sleep interval before the next loop, if applicable
    if ($i -lt ($actualLoops - 1)) {
        Start-Sleep -Seconds $sleepInterval
    }
}

# Calculate the percentage of successful checks
$successPercentage = [math]::Floor(($successCount / $actualLoops) * 100)

# Log the final success percentage
Log-Entry "Final Success Percentage: $successPercentage%"

# Output only the success percentage for Aria Operations integration
$successPercentage
