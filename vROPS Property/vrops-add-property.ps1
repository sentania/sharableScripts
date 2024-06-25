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
     $vmhosts+= $temp

     $ED=[Math]::Floor([decimal](Get-Date(Get-Date).ToUniversalTime()-uformat "%s"))

     $json = 
     '{
    "property-content" : [
        {
            "statKey": "CustomProps|Owner",
            "timestamps": [123345],
            "values" :[
                "sbowe3"
            ],
            "others" :[],
            "otherAttributes": {}
        }
    ]
    }'
}
#endregion
#REMOVE ALL HOSTS WITHOUT A SCHEDULE GROUP



$bodyJSON = $validinput | convertto-json -Depth 100
$putResults = Invoke-RestMethod "https://$vROPSFQDN/suite-api/internal/costdrivers/servergroups?hci=true&_no_links=true" -Method 'PUT' -Headers $secHeaders -Body $bodyJSON