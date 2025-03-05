param (
    [Parameter(Mandatory=$true)][string]$vCenterHost,
    [Parameter(Mandatory=$true)][string]$vCUsername,
    [Parameter(Mandatory=$true)][string]$vcPassword,
    [Parameter(Mandatory=$true)][string]$hostUser,
    [Parameter(Mandatory=$true)][string]$hostPassword,
    [Parameter(Mandatory=$true)][string]$hostLicenseKey
)
try 
{
    Write-Host "Correcting licensings on hosts in vCenter: $vCenterhost" -ForegroundColor Green
    
    $vCenterConnection = Connect-VIServer -Server $vCenterHost -User $vCUsername -Password $vcPassword

    #we will assume we should update all the hosts

    $vmhosts = Get-VMHost

    foreach ($vmhost in $vmhosts)
    {  
        try
        {
            Write-Host "Correcting licensings on host: $vmhost" -ForegroundColor Green
            $vmHostConnection = Connect-VIServer -Server $vmhost -user $hostUser -password $hostPassword
            set-vmhost -Server $vmHostConnection -LicenseKey $hostLicenseKey -Confirm:$false
            if ($vmhost.ConnectionState -ne 'Connected')
            {
                set-vmhost -server $vCenterConnection -VMHost $vmhost -State Connected -Confirm:$false
            }
            disconnect-viserver -Server $vmHostConnection -Confirm:$false
        }
        catch 
        {
            Write-host "Unable to connect to ESX Host $vmhost"
            
        }
    }

    Disconnect-viserver  -Server $vCenterConnection -Confirm:$false
}

catch 
{
    Write-host "Unable to connect to vCenter server $vCenterhost"
}