$applicationTags = import-csv .\app-mapping.csv
###expected format:  groupname, grouptag, grouptagcategory
$portfolioApplicationMappings = import-csv .\portfolio-app-mapping.csv
###expected format: groupname, porfolioCode
$vROPSFQDN = "vrops.lab.sentania.net"
$vROPSuser = "admin"
$vROPSpasswd = "p0w3R2win!"


$applicationGroupTYpe = "(Custom) Application"
$portfolioGroupType = "(Custom) Porfolio"

#region AUTHENTICATE TO vROPS
$firstHeaders = New-Object “System.Collections.Generic.Dictionary[[String],[String]]”

$firstHeaders.Add(“Content-Type”, “application/json; utf-8”)

$firstHeaders.Add(“Accept”, “application/json”)

#Enter your username and password. I just tried with local user.

$firstBody = “{

`n  `”username`” : `”$vROPSuser`”,
`n  `”password`” : `”$vROPSpasswd`”,
`n  `”others`” : [ ],
`n  `”otherAttributes`” : { }
`n}”

#Enter your vROps IP or FQDN

$firstResponse = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/auth/token/acquire" -Method ‘POST’ -Headers $firstHeaders -Body $firstBody

$firstResponse | ConvertTo-Json

#We get the token.

$token = $firstResponse.token
$secHeaders = New-Object “System.Collections.Generic.Dictionary[[String],[String]]”
$secHeaders.Add(“Content-Type”, “application/json; utf-8”)
$secHeaders.Add(“Accept”, “application/json”)
$secHeaders.Add(“Authorization”, “vRealizeOpsToken $token”)

#endregion

#region Pull list of all existing groups
$groupList = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/resources/groups" -Method 'GET' -Headers $secHeaders
$groupListjson = $grouplist.groups | convertto-json -Depth 99

$groupobjectList = $groupListjson | ConvertFrom-Json

#endregion
#for each application in our input file we will create a group of the
foreach ($applicationTag in $applicationTags)
{
$groupName = $applicationTag.groupname
$grouptag = $applicationTag.grouptag
$groupcategory =  $applicationtag.grouptagcatagory

foreach ($groupobject in $groupobjectList)
{
    $present = $FALSE
    if ($groupname -eq $groupobject.resourceKey.name)
    {
        $present = $TRUE
    }
    Write-host $present
}

#if the group exists - don't create it
if ($present -eq $FALSE)
{
$secBody = “{
 ""resourceKey"": {
        ""name`": ""$groupName"",
        ""adapterKindKey"": ""Container"",
        ""resourceKindKey"": ""$applicationGroupTYpe"" 
    },
    ""autoResolveMembership"": true,
    ""membershipDefinition"": {
        ""rules"": [
            {
                ""resourceKindKey"": {
                    ""resourceKind"": ""VirtualMachine"",
                    ""adapterKind"": ""VMWARE""
                },
                 ""resourceTagConditionRules"" : [ {
                   ""category"" : ""$groupcategory"",
                   ""compareOperator"" : ""EQ"",
                   ""stringValue"" : ""$grouptag""
            }
        ]
}]
}
}”

$secResponse = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/resources/groups" -Method ‘POST’ -Headers $secHeaders -Body $secBody

}

foreach ($portfolioApplicationMapping in $portfolioApplicationMappings)
{
$groupName = $portfolioApplicationMapping.groupname
$portfoliocode = $portfolioApplicationMapping.portfoliocode


$secBody = “{
 ""resourceKey"": {
        ""name`": ""$groupName"",
        ""adapterKindKey"": ""Container"",
        ""resourceKindKey"": ""$portfolioGroupType"" 
    },
    ""autoResolveMembership"": true,
    ""membershipDefinition"": {
        ""rules"": [
            {
                ""resourceKindKey"": {
                    ""resourceKind"": ""$applicationGroupTYpe"",
                    ""adapterKind"": ""Container""
                },
                 ""resourceNameConditionRules"" : [ {
                   ""name"" : ""$portfoliocode"",
                   ""compareOperator"" : ""CONTAINS""
                   
            }
        ]
}]
}
}”

$secResponse = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/resources/groups" -Method ‘POST’ -Headers $secHeaders -Body $secBody
}
