<#
.SYNOPSIS
Creates or updates vROPS groups based on CSV input data.

.DESCRIPTION
This script automates the creation and population of groups in vRealize Operations (vROPS). It reads group definitions and membership information from CSV files, retrieves the current inventory from vROPS, and then creates or updates groups accordingly. If a group exists, it is updated to reflect the CSV data; if it does not exist, it is created.

.PARAMETER vROPSUser
Specifies the username for authentication to the vROPS instance.

.PARAMETER vROPSpasswd
Specifies the password for authentication to the vROPS instance.

.PARAMETER vROPSFQDN
Specifies the fully qualified domain name (FQDN) of the vROPS server.

.PARAMETER ignoreSSL
(Optional) If set to $true, the script will ignore SSL certificate errors. Default is $false.  
**Note:** Use with caution in production environments.

.PARAMETER groupInputListCsv
Specifies the path to the CSV file containing the group definitions. The CSV should have columns like `groupname` and `resourceKindKey`.

.PARAMETER groupMembershipInputListCsv
Specifies the path to the CSV file containing group membership information. The CSV should have columns such as `objectname`, `resourcekind`, and `groupname`.

.EXAMPLE
.\create-CustomAriaOpsGroup.ps1 -vROPSUser "admin" -vROPSpasswd "password" -vROPSFQDN "vrops.example.com" -groupInputListCsv "C:\Data\groups.csv" -groupMembershipInputListCsv "C:\Data\groupMembership.csv" -ignoreSSL $true

.NOTES
Author: Scott Bowe 
Date: 2025-03-05  
Version: 1.0
Contact: scott.bowe@broadcom.com / scottb@sentania.net
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$vROPSUser,

    [Parameter(Mandatory = $true)]
    [string]$vROPSpasswd,

    [Parameter(Mandatory = $true)]
    [string]$vROPSFQDN,

    [Parameter(Mandatory = $false)]
    [bool]$ignoreSSL = $false,

    [Parameter(Mandatory = $true)]
    [string]$groupInputListCsv,

    [Parameter(Mandatory = $true)]
    [string]$groupMembershipInputListCsv

)
if ($ignoreSSL -eq $true)
{
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}

#region Read CSV Files
# Groups CSV: groupname,resourceKindKey
$groupInputList = Import-Csv -Path $groupInputListCsv

# Group Membership: objectname,resourcekind,groupname
$groupMembershipInputList = Import-Csv -Path $groupMembershipInputListCsv
#endregion

#region Define Endpoints
$vropsResourcesEndpoint = "https://$vROPSFQDN/suite-api/api/resources"
$vropsGroupsEndpoint = "https://$vROPSFQDN/suite-api/api/resources/groups"
#endregion

#region AUTHENTICATE TO vROPS
$firstHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$firstHeaders.Add("Content-Type", "application/json; utf-8")
$firstHeaders.Add("Accept", "application/json")

$authBody = "{
  `"username`" : `"$vROPSUser`",
  `"password`" : `"$vROPSpasswd`",
  `"others`" : [ ],
  `"otherAttributes`" : { }
}"
$authResponse = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/auth/token/acquire" -Method POST -Headers $firstHeaders -Body $authBody
$token = $authResponse.token

$secHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$secHeaders.Add("Content-Type", "application/json; utf-8")
$secHeaders.Add("Accept", "application/json")
$secHeaders.Add("Authorization", "vRealizeOpsToken $token")
$secHeaders.Add("X-vRealizeOps-API-use-unsupported", "true")
#endregion

#our goal is to create and populate groups in vROPS.
#we will work from a set of CSVs read from this directory
#if the group does not exist we will create it, and populate it with the specified objects
#if the group does exist we will update it, adding or removing members as needed

#region Batch query to aria operations to get group data and object data
Write-Output "Retrieving vROPS resource inventory..."
try {
    # vrops defaults to a page size of 1000 - which is a problem in a large environment
    #to work around that we are going to set a really big page size and only retrieve objects that someone has told us to get metrics for
    $resourceKindList = @()
    foreach ($metricMap in $metricsMapping)
    {
        $resourceKindList += $metricMap.ResourceKind
    }
    $resourceKindQuery = ($resourceKindList | ForEach-Object { "resourceKind=$($_)" }) -join "&"
    $url = $vropsResourcesEndpoint + "?pageSize=100000"
    $url = $url + "&$resourceKindQuery"
    $url += "&_no_links=true"
    $allResourcesResponse = Invoke-RestMethod -Uri $url -Method Get -Headers $secHeaders
}
catch {
    Write-Error "Failed to retrieve resources from vROPS: $_"
    exit 1
}

if ($allResourcesResponse.resourceList) {
    $allResources = $allResourcesResponse.resourceList
} else {
    $allResources = $allResourcesResponse
}

# Build a mapping array with resourceName, resourceId, and resourceKindKey.
$resourceMapping = @()
foreach ($resource in $allResources) {
    $temp = "" | Select-Object resourceName, resourceId, resourceKindKey
    $temp.resourceName = $resource.resourcekey.name
    $temp.resourceId = $resource.identifier
    $temp.resourceKindKey = $resource.resourcekey.resourceKindKey
    $resourceMapping += $temp
}
Write-Output "Found $($resourceMapping.Count) resources in Aria Ops inventory."

#We are retrieving group inventory again even though it's technically part of the all resources to simpliy processing since the groups have different resource kinds and adapters/etc.

Write-output "Retrieving vROPS Group Inventory"
try 
{
    $url = $vropsGroupsEndpoint
    $groupList = Invoke-RestMethod -Uri $url -Method Get -Headers $secHeaders
    $groupListjson = $grouplist.groups | convertto-json -Depth 99

    $groupobjectList = $groupListjson | ConvertFrom-Json
}

catch
{
    Write-Error "Failed to retrieve groups from vROPS: $_"
    exit 1
}

# Build a mapping array with our groups
$groupMapping = @()
foreach ($group in $groupobjectList)
{
    $temp = "" | Select-Object resourceName, resourceId, resourceKindKey, membershipDefinition
    $temp.resourceName = $group.resourcekey.name
    $temp.resourceId = $group.id
    $temp.resourceKindKey = $group.resourcekey.resourceKindKey
    $temp.membershipDefinition = $group.membershipDefinition
    $groupMapping += $temp
}
Write-Output "Found $($groupMapping.Count) groups in vROPS inventory."
#end region

#region manage group status
#inventory existing groups and create an object for us to use later to cycle through and create/update them
$ourGroups = @()
foreach ($group in $groupInputList)
{
    $temp = "" | Select-Object resourceName, resourceID, resourceKindKey, membershipDefinition, present
    $temp.present = $FALSE
    $temp.resourceName = $group.groupname
    $temp.resourceKindKey = $group.resourceKindKey

    if ($groupMapping.resourceName.contains($group.groupname))
    {
        $temp.present = $TRUE
        $temp.resourceId = ($groupMapping | where-object {$_.resourceName -eq $group.groupname}).resourceId
        $temp.resourceKindKey = ($groupMapping | where-object {$_.resourceName -eq $group.groupname}).resourceKindKey
        $temp.membershipDefinition = ($groupMapping | where-object {$_.resourceName -eq $group.groupname}).membershipDefinition #given that I'm not writing this to be additive, I'm not sure why I did this, but here we are
    }
    $ourGroups += $temp    
}
#end region

#region create/update groups
#this is a bit inefficient, because we could have done this in our logic above, but this is a bit more readable
#this script is intended to be declaritive - if an object is not listed in the groupmembership csv - it will be removed from the group - it is not additive
foreach ($group in $ourGroups)
{
    #pull objects that need to belong to this group
    $thisGroupsObjects = $groupMembershipInputList | where-object {$_.groupname -eq $group.resourceName}
    $thisGroupObjectsId = @()
    foreach ($object in $thisGroupsObjects )
    {
        #look up the object IDs for each
        Write-host "Looking up vROPS object for:" $object.objectname
        $tempID = ($allresources | where-object {$_.resourcekey.name -eq $object.objectname} | where-object {$_.resourcekey.resourceKindKey -eq $object.resourcekind}).identifier
        if ($tempID)
        {
            $thisGroupObjectsId += $tempID
        }
        else
        {
            Write-host "Unabled to find Aria Ops Object for: " $object.objectname
        }
    }
    #make our object ID array an json for the post/put
    $thisGroupObjectsIdJSON = $thisGroupObjectsId | convertto-json
    if ($thisGroupObjectsId.count -eq 1)
    {
        $thisGroupObjectsIdJSON = "[" + $thisGroupObjectsIdJSON +"]"
    }
    if ($group.present) #if the group exists we must update it
    {
        #assemble the JSON body for group update
        $thisGroupId = $group.resourceID
        $thisGroupName = $group.resourceName
        $thisGroupResourceNameKind = $group.resourceKindKey
        $postBody = "{
            ""id"": ""$thisGroupId"",
            ""resourceKey"": {
                ""name`": ""$thisGroupName"",
                ""adapterKindKey"": ""Container"",
                ""resourceKindKey"": ""$thisGroupResourceNameKind"" 
            },
            ""autoResolveMembership"": false,
            ""membershipDefinition"": {
            ""includedResources"": $thisGroupObjectsIdJSON
            }
        }"
        try 
        {
            Write-host "Updating Group: " $thisGroupName
            $response = Invoke-RestMethod "$vropsGroupsEndpoint" -Method "PUT" -Headers $secHeaders -Body $postBody
        }
        catch
        {
            Write-host $_ -ForegroundColor Red
            Write-host "Failed to update group:" $group.resourceName -ForegroundColor Red
        }
    }
    #the group doesn't exist, create it
    else
    {
        #assemble the JSON body for group creation
        $thisGroupName = $group.resourceName
        $thisGroupResourceNameKind = $group.resourceKindKey
        $postBody = "{
            ""resourceKey"": {
                ""name`": ""$thisGroupName"",
                ""adapterKindKey"": ""Container"",
                ""resourceKindKey"": ""$thisGroupResourceNameKind"" 
            },
            ""autoResolveMembership"": false,
            ""membershipDefinition"": {
               ""includedResources"": $thisGroupObjectsIdJSON
            }
        }"
        try 
        {
            Write-host "Creating Group: " $thisGroupName
            $response = Invoke-RestMethod "$vropsGroupsEndpoint" -Method "POST" -Headers $secHeaders -Body $postBody
        }
        catch
        {
            Write-host $_ -ForegroundColor Red
            Write-host "Failed to Create group:" $group.resourceName -ForegroundColor Red
            $postbody
            
        }
    }
}
#endregion




