# Prompt for credentials
$cred = Get-Credential

# Connect to vCenter
Connect-VIServer -Server lab-vcf-w01-vc.int.sentania.net -Credential $cred

# Get all VMHosts
$vmhosts = Get-VMHost
$results = @()
foreach ($vmHost in $vmhosts)
{
    $connectedVdswitches = $vmhost | get-vdswitch

    foreach ($vSwitch in $connectedVdswitches)
    {
        $connectedUplinks = (get-vdport -vdswitch $vSwitch -uplink) | where {$_.ExtensionData.connectee.connectedentity.value -eq $vmhost.ExtensionData.moref.value}
        #get host network adapters
        $vmHostNetworkAdapters = Get-VMHostNetworkAdapter -VMHost $vmhost -Physical
        foreach ($connectedUplink in $connectedUplinks)
        {
                #get this network adapter
                $thisNetworkAdapter = $vmHostNetworkAdapters | where {$_.Name -eq $connectedUplink.connectedentity}
                
                $tempcollection = "" | select VMhost, VMNIC, Driver, DriverVersion, FirmwareVersion, MacAddress, LinkStatus, speed, uplinkName
                $tempcollection.VMhost = $vmhost.Name
                $tempcollection.VMNIC = $connectedUplink.connectedentity
                $tempcollection.uplinkName = $connectedUplink.name
                $tempcollection.LinkStatus = $connectedUplink.IsLinkUp
                $tempcollection.speed = $thisNetworkAdapter.bitratepersec
                $tempcollection.MacAddress = $thisNetworkAdapter.mac
                $tempcollection.driver = $thisNetworkAdapter.ExtensionData.Driver
                $tempcollection.DriverVersion = $thisNetworkAdapter.ExtensionData.DriverVersion
                $tempcollection.FirmwareVersion = $thisNetworkAdapter.ExtensionData.FirmwareVersion
                $results += $tempcollection

        }
    }
    

}
# Output to terminal
$results | Format-Table -AutoSize

# Export to CSV
$csvPath = "C:\temp\vmnic_status_map.csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation

Write-Host "`nCSV exported to: $csvPath"
Disconnect-VIServer * -Confirm:$false
