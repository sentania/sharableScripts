#authenticate
#region AUTHENTICATE TO vROPS
$firstHeaders = New-Object “System.Collections.Generic.Dictionary[[String],[String]]”
$firstHeaders.Add(“Content-Type”, “application/json; utf-8”)
$firstHeaders.Add(“Accept”, “application/json”)
#Enter your username and password. I just tried with local user.
$vROPSUser = "admin"
$vROPSpasswd = "VMware1!"
$vROPSFQDN = "vrops.lab.sentania.net"
$authBody = “{
`n  `”username`” : `”$vROPSuser`”,
`n  `”password`” : `”$vROPSpasswd`”,
`n  `”others`” : [ ],
`n  `”otherAttributes`” : { }
`n}”

#Enter your vROps IP or FQDN

$authResponse = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/auth/token/acquire" -Method ‘POST’ -Headers $firstHeaders -Body $authBody

$authResponse | ConvertTo-Json

#We get the token.

$token = $authResponse.token
$secHeaders = New-Object “System.Collections.Generic.Dictionary[[String],[String]]”
$secHeaders.Add(“Content-Type”, “application/json; utf-8”)
$secHeaders.Add(“Accept”, “application/json”)
$secHeaders.Add(“Authorization”, “vRealizeOpsToken $token”)
$secHeaders.Add("X-vRealizeOps-API-use-unsupported", "true")
#endregion

#INGEST LIST OF SERVICE TAG TO SCHEDULE GROUP MAPPINGS
$servicetagMapping = Import-Csv .\servicetag-mapping.csv
$scheduleGroups = Import-csv .\scheduleGroupCost.csv
$GBP2USD = 2.44
#INGEST SCHEDULE GROUP COSTS


#region get all VM hosts from vROPS
$vmhostGroups = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/resources?resourceKind=HostSystem&_no_links=true" -Method 'GET' -Headers $secHeaders
$vmhostGroups = $vmhostGroups.resourceList
$vmhosts = @()
foreach ($vmhost in $vmhostGroups)
{
    $temp = "" | select vmhost, id, address, servicetag,scheduleGroup
    $temp.vmhost = $vmhost.resourcekey.name
    $temp.id = $vmhost.identifier
    $id = $temp.id
    $temp.address = $vmhost.resourceKey.name
    
    #we need to locate the service tag of the host
    $properties = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/resources/$id/properties" -Method 'GET' -Headers $secHeaders
    foreach ($prop in $properties.property )
    {
        if ($prop.name -eq "hardware|serviceTag")
        {
            $temp.servicetag = $prop.value
        }

    }
    $temp.scheduleGroup = ($servicetagMapping | where {$_.servicetag -eq $temp.servicetag}).scheduleGroup
    $vmhosts+= $temp
}
#endregion
#REMOVE ALL HOSTS WITHOUT A SCHEDULE GROUP

$vmhosts = $vmhosts | where {$_.scheduleGroup -ne $NULL} 

#MERGE SERVICE TAG and SCHEDULE GROUP TO HOST OBJECTS and COST
#We assume the cost per schedule group is a total, so we need to cycle through our hosts and schedule groups and count them, to get a "Unit" cost
$scheduleGroupsAdjusted = @()
foreach ($scheduleGroup in $scheduleGroups)
{
    
    $temp = "" | select scheduleGroup, UnitCost
    $scheduleGrouphostCount = ($vmhosts | where {$_.scheduleGroup -eq 2}).count
    $scheduleGroupUnitCost = $scheduleGroup.cost / $scheduleGrouphostCount
    if ($scheduleGroup.currency -eq "GBP")
    {
        #We are assuming vROPS is operating in USD
        $scheduleGroupUnitCost = $scheduleGroup.cost / $scheduleGrouphostCount * $GBP2USD
    }
    else 
    {
        $scheduleGroupUnitCost = $scheduleGroup.cost / $scheduleGrouphostCount
    }
    $temp.scheduleGroup = $scheduleGroup.scheduleGroup
    $temp.unitCost = $scheduleGroupUnitCost

    $scheduleGroupsAdjusted += $temp

}


#get server groups
$vmHostCostGroupsResults = Invoke-RestMethod "https://$vROPSFQDN/suite-api/internal/costdrivers/servergroups?hci=true&_no_links=true" -Method 'GET' -Headers $secHeaders


$vmhostCostGroups = $vmHostCostGroupsResults.serverHardwareGroupsCostCOnfigurations


foreach ($serverGroup in $vmhostCostGroups)
{
    $newDefaultbatch = @()
    $serverBatch = @()
    #let's cycle through each server in the default batch - if it's in our list of servers - we'll remove it and add it
    foreach ($server in $serverGroup.defaultBatch.serverDetails)
    {
        if ($vmhosts | where {$_.id -eq $server.serverID})
        {
            #this server exists as part of a custom batch - so we will put it there
            #for ease of coding each server will be part of it's own batch
            $serverDetails = "" | select serverId, serverAddress
            $temp = "" | select costPerServer, serverDetails, purchaseDate, purchaseType, computePercentage
            $temp.purchaseType = "Leased"
            $temp.computePercentage = 100
            $temp.purchaseDate = "1556668800000"
            $temp.costPerserver = ($scheduleGroupsAdjusted | where {$_.scheduleGroup -eq ($vmhosts | where {$_.id -eq $server.serverID}).scheduleGroup }).unitcost
            $temp.serverDetails = @()
            $serverdetails.serverID = $server.serverId
            $serverDetails.serverAddress = $server.serverAddress
            $temp.serverDetails += $serverDetails
            $serverbatch += $temp
        }
        else 
        {
            #This server is not part of a schedule group, so we will keep it in the default batch
            $newDefaultbatch += $server
        }
    }
    $serverGroup.defaultBatch.serverDetails = $newDefaultbatch
    $serverGroup.serverBatchCostConfigurations = $serverBatch
}

#our groups should be updated - now we need to finese the format a bit
$validInput = "" | select serverHardwareGroupsCostConfigurations
$validinput.serverHardwareGroupsCostConfigurations = $vmhostCostGroups

$bodyJSON = $validinput | convertto-json -Depth 100
$putResults = Invoke-RestMethod "https://$vROPSFQDN/suite-api/internal/costdrivers/servergroups?hci=true&_no_links=true" -Method 'PUT' -Headers $secHeaders -Body $bodyJSON