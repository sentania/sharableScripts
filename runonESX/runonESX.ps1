<#
.SYNOPSIS
 Executes a Python script on all ESXi hosts in a vCenter, with prerequisite checks.

.PARAMETER vcenterServer
 FQDN or IP of your vCenter.

.PARAMETER scriptPath
 Local path to the Python script you want to run.

.PARAMETER remotePath
 Remote path on ESXi hosts. Default: /tmp/script.py

.PARAMETER scriptParams
 Optional parameters to pass to the Python script when executed.

.PARAMETER vCenterUser
 Username for connecting to vCenter.

.PARAMETER vCenterPasswd
 Password for the vCenterUser (will be converted to a secure string internally).

.PARAMETER esxiUser
 Username on the ESXi hosts. Default: root

.PARAMETER esxiPass
 Password on the ESXi hosts.

.PARAMETER ignoreSSL
 Switch to ignore invalid SSL certificates when connecting to vCenter. Default: $false

 .PARAMETER VMHostFilter
 (Optional) Pass in a string to filter the hosts selected for execution. 

.EXAMPLE
 .\Run-OnEsx.ps1 `
   -vcenterServer vc.example.com `
   -scriptPath C:\tools\do_stuff.py `
   -vCenterUser administrator@vsphere.local `
   -vCenterPasswd 'VcEnt3rP@ss!' `
   -esxiPass 'ESXiP@ss!' `
   -scriptParams '-arg1 value1 -arg2 value2' `
   -ignoreSSL
   -VMHostFilter "*prod*esx*"
#>

param(
    [Parameter(Mandatory)]
    [string]$vcenterServer,
    [Parameter(Mandatory)]
    [string]$scriptPath,
    [string]$remotePath = "/tmp/script.py",
    [string]$scriptParams,
    [Parameter(Mandatory)]
    [string]$vCenterUser,
    [Parameter(Mandatory)]
    [string]$vCenterPasswd,
    [string]$esxiUser   = "root",
    [Parameter(Mandatory)]
    [string]$esxiPass,
    [boolean]$ignoreSSL = $false,
    [string]$VMHostFilter = "*"
)

function Abort([string]$msg) {
    Write-Error $msg
    exit 1
}

if ($ignoreSSL)
{
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
}
Write-Host "=== Prerequisite Checks ===" -ForegroundColor Yellow

# 1. PowerShell Core check (version 7+)
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Abort "PowerShell Core 7 or higher is required. Current version: $($PSVersionTable.PSVersion)"
}
Write-Host "✔ PowerShell Core version $($PSVersionTable.PSVersion) detected."

# 2. PowerCLI module check
if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
    Abort "VMware.PowerCLI module not found. Install with: Install-Module -Name VMware.PowerCLI"
}
Write-Host "✔ VMware.PowerCLI module is available."

# 3. ssh check
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Abort "'ssh' not found in PATH. Ensure OpenSSH client is installed and in your PATH."
}
Write-Host "✔ ssh found."

# 4. scp check
if (-not (Get-Command scp -ErrorAction SilentlyContinue)) {
    Abort "'scp' not found in PATH. Ensure OpenSSH client is installed and in your PATH."
}
Write-Host "✔ scp found."

# 5. sshpass check
if (-not (Get-Command sshpass -ErrorAction SilentlyContinue)) {
    Abort "'sshpass' not found in PATH. Install sshpass or configure key-based auth instead."
}
Write-Host "✔ sshpass found."

Write-Host "All prerequisites met. Proceeding..." -ForegroundColor Green
Write-Host ""

# Ensure VMware.PowerCLI is loaded
Import-Module VMware.PowerCLI -ErrorAction Stop

$secStringPassword = ConvertTo-SecureString $vCenterPasswd -AsPlainText -Force

$vcenterCred = New-Object System.Management.Automation.PSCredential ($vCenterUser, $secStringPassword)

# Connect to vCenter
Connect-VIServer -Server $vcenterServer -Credential $vcenterCred | Out-Null

# Prepare result collection
$results = @()

# Get all connected ESXi hosts
$vmhosts = Get-VMHost -name $VMHostFilter | Where-Object { $_.ConnectionState -eq "Connected" }

foreach ($vmhost in $vmhosts) {
    $record = [PSCustomObject]@{
        Host    = $vmhost.Name
        Status  = "Pending"
        Message = ""
    }
    try {
        Write-Host "`n=== $($vmhost.Name) ===" -ForegroundColor Cyan

        # Enable SSH service
        $svc = Get-VMHostService -VMHost $vmhost | Where-Object { $_.Key -eq "TSM-SSH" }
        if (-not $svc.Running) {
            Write-Host "Starting SSH service..."
            Start-VMHostService -HostService $svc | Out-Null
            do {
                Start-Sleep 1
                $svc = Get-VMHostService -VMHost $vmhost | Where-Object { $_.Key -eq "TSM-SSH" }
            } while (-not $svc.Running)
        }

        # Copy script
        Write-Host "Copying `$scriptPath` → ${vmhost}:$remotePath..."
        sshpass -p $esxiPass scp -o StrictHostKeyChecking=no $scriptPath "$esxiUser@$($vmhost.Name):$remotePath"

        # Run script remotely and capture exit code
        Write-Host "Executing script on $vmhost..."
        # Build a shell snippet that:
        #  1. runs the Python script,
        #  2. saves its exit code ($?),
        #  3. echoes it for visibility,
        #  4. then exits with that same code so ssh's exit reflects it.
        $remoteCmd = @"
python $remotePath $scriptParams
rc=\$?
echo ExitCode:\$rc
exit \$rc
"@

        Write-Host "Executing script on $($vmhost.Name)…"
        sshpass -p $esxiPass ssh -o StrictHostKeyChecking=no `
        "$esxiUser@$($vmhost.Name)" $remoteCmd

        # Now inspect ssh’s exit code (which matches the Python exit code):
        if ($LASTEXITCODE -eq 0) {
            $record.Status  = "Success"
        }
        else {
            $record.Status  = "Failed"
            $record.Message = "Remote script exited with code $LASTEXITCODE"
        }

        # Stop SSH service
        Write-Host "Stopping SSH service..."
        Stop-VMHostService -HostService $svc -Confirm:$false | Out-Null
    }
    catch {
        $record.Status  = "Failed"
        $record.Message = $_.Exception.Message
    }
    finally {
        $results += $record
    }
}

# Disconnect cleanly
Disconnect-VIServer -Server $vcenterServer -Confirm:$false | Out-Null
if ($ignoreSSL)
{
    Set-PowerCLIConfiguration -InvalidCertificateAction unset -Confirm:$false
}

# Output a summary table
Write-Host "`n=== Summary ===" -ForegroundColor Green
$results | Format-Table -AutoSize
