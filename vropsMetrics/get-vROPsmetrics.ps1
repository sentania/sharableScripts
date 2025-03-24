<#
.SYNOPSIS
    Extracts batched performance metrics from vRealize Operations for a set of objects.

.DESCRIPTION
    This script authenticates to vRealize Operations (vROps), retrieves the resource inventory, and then
    performs a batched GET call to query metric statistics for multiple resource IDs. The input consists
    of two CSV files:
      - An objects CSV with columns: ObjectName, ResourceKind.
      - A metrics CSV whose first column is ResourceKind and subsequent columns list the statKeys
        (e.g. "cpu|usage_average", "mem|workload") to query.
    
    The user must supply a valid interval type (one of MINUTES, HOURS, SECONDS, DAYS, WEEKS, MONTHS, or YEARS)
    and a rollup type (one of SUM, AVG, MIN, MAX, NONE, LATEST, or COUNT). These parameters are passed directly
    to the API.

.PARAMETER vROPSUser
    The username for vROps API authentication.

.PARAMETER vROPSpasswd
    The password for vROps API authentication.

.PARAMETER vROPSFQDN
    The fully qualified domain name or IP address of the vROps instance.

.PARAMETER StartTime
    The start of the metric query time range (as a DateTime).

.PARAMETER EndTime
    The end of the metric query time range (as a DateTime).

.PARAMETER RollupInterval
    The rollup interval to use. Valid values (case-insensitive) are:
    MINUTES, HOURS, SECONDS, DAYS, WEEKS, MONTHS, YEARS.
    (User input is forced to uppercase.)

.PARAMETER RollupType
    The rollup type to use. Valid values (case-insensitive) are:
    SUM, AVG, MIN, MAX, NONE, LATEST, COUNT.
    (User input is forced to uppercase.)

.PARAMETER ObjectCsv
    The path to the CSV file containing objects. Expected columns: ObjectName, ResourceKind.

.PARAMETER MetricsCsv
    The path to the CSV file mapping ResourceKind to one or more statKeys.
    The CSV should have a header row where the first column is ResourceKind and subsequent columns
    contain the statKey values.

.PARAMETER OutputDirectory
    The directory where the output CSV files will be saved (defaults to the current directory).

.PARAMETER ignoreSSL
    If this is set to true, it will ignore SSL validation.  Default is $FALSE

.EXAMPLE
    .\Get-vROpsMetrics.ps1 -vROPSUser admin -vROPSpasswd P@ssw0rd -vROPSFQDN operations.example.com `
        -StartTime "2025-02-20T00:00:00" -EndTime "2025-02-20T23:59:59" `
        -RollupInterval MINUTES -RollupType AVG `
        -ObjectCsv "C:\Inputs\objects.csv" -MetricsCsv "C:\Inputs\metrics.csv" `
        -OutputDirectory "C:\Outputs" `
        -ignoreSSL $false

.NOTES
    Only VirtualMachine object types have been validated in testing. Other object types (e.g., HostSystem)
    may not return any data.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$vROPSUser,

    [Parameter(Mandatory = $true)]
    [string]$vROPSpasswd,

    [Parameter(Mandatory = $true)]
    [string]$vROPSFQDN,

    [Parameter(Mandatory = $true)]
    [datetime]$StartTime,

    [Parameter(Mandatory = $true)]
    [datetime]$EndTime,

    # User must supply one of these valid values:
    [Parameter(Mandatory = $true)]
    [ValidateSet("MINUTES", "HOURS", "SECONDS", "DAYS", "WEEKS", "MONTHS", "YEARS")]
    [string]$RollupInterval,

    [Parameter(Mandatory = $true)]
    [ValidateSet("SUM", "AVG", "MIN", "MAX", "NONE", "LATEST", "COUNT")]
    [string]$RollupType,

    [Parameter(Mandatory = $true)]
    [string]$ObjectCsv,

    [Parameter(Mandatory = $true)]
    [string]$MetricsCsv,

    [Parameter(Mandatory = $false)]
    [bool]$ignoreSSL = $false,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = "."
)
if ($ignoreSSL = $true)
{
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}

#region Read CSV Files
# Objects CSV: expected columns: ObjectName, ResourceKind
$objectList = Import-Csv -Path $ObjectCsv -Header "ObjectName", "ResourceKind"

# Metrics CSV: first column is ResourceKind; subsequent columns are statKeys.
$metricsMapping = Import-Csv -Path $MetricsCsv
#endregion

#region Define Endpoints
$vropsResourcesEndpoint = "https://$vROPSFQDN/suite-api/api/resources"
$vropsStatisticsEndpoint = "https://$vROPSFQDN/suite-api/api/resources/stats"
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
Write-Output "Found $($resourceMapping.Count) resources in vROPS inventory."


# Force Rollup parameters to upper case as expected by the API.
$RollupInterval = $RollupInterval.ToUpper()
$rollupTypeUpper = $RollupType.ToUpper()

#region Batch Stats Query and Processing

foreach ($mapping in $metricsMapping) {
    $resourceKind = $mapping.ResourceKind.ToLower()
    Write-Output "Processing resource kind: $resourceKind"

    $objects = $objectList | Where-Object { $_.ResourceKind.ToLower() -eq $resourceKind }
    if ($objects.Count -eq 0) {
        Write-Output "No objects found for resource kind '$resourceKind'. Skipping..."
        continue
    }

    # Build an array of statKeys (all columns except ResourceKind)
    $statKeys = $mapping.PSObject.Properties |
                Where-Object { $_.Name -ne "ResourceKind" } |
                ForEach-Object { $_.Value } |
                Where-Object { $_ -and $_.Trim().Length -gt 0 }

    # Build an array of requested resources (FriendlyName and ResourceId)
    $requestedResources = @()
    foreach ($obj in $objects) {
        $friendlyName = $obj.ObjectName
        $lookupName = $friendlyName.ToLower()
        $match = $resourceMapping | Where-Object { $_.resourceName.ToLower() -eq $lookupName }
        if ($match) {
            $requestedResources += [PSCustomObject]@{
                FriendlyName = $friendlyName
                ResourceId   = $match.resourceId
            }
        }
        else {
            Write-Warning "Resource '$friendlyName' not found in inventory."
        }
    }
    if ($requestedResources.Count -eq 0) {
        Write-Output "No valid resource IDs for resource kind '$resourceKind'. Skipping..."
        continue
    }

    # Build the GET URL including multiple resourceId and statKey parameters.
    $resourceIdsQuery = ($requestedResources | ForEach-Object { "resourceId=$($_.ResourceId)" }) -join "&"
    $startMs = [long](($StartTime - (Get-Date '1970-01-01T00:00:00Z')).TotalMilliseconds)
    $endMs   = [long](($EndTime   - (Get-Date '1970-01-01T00:00:00Z')).TotalMilliseconds)
    $url = $vropsStatisticsEndpoint + "?begin=$startMs&end=$endMs"
    $url += "&intervalType=$RollupInterval"
    $url += "&rollUpType=$rollupTypeUpper"
    $url += "&$resourceIdsQuery"
    foreach ($key in $statKeys) {
        $url += "&statKey=" + [System.Web.HttpUtility]::UrlEncode($key)
    }
    $url += "&_no_links=true"

    Write-Output "Batch querying metrics for $($requestedResources.Count) resources of kind '$resourceKind'."
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $secHeaders
    }
    catch {
        Write-Error "Failed to retrieve batched metrics: $_"
        continue
    }

    # Build a lookup dictionary from resourceId to its returned data.
    $returnedData = @{}
    if ($response.values) {
        foreach ($entry in $response.values) {
            $returnedData[$entry.resourceId] = $entry
        }
    }

    $results = @()
    foreach ($res in $requestedResources) {
        if ($returnedData.ContainsKey($res.ResourceId)) {
            $valueEntry = $returnedData[$res.ResourceId]
            $statList = $valueEntry."stat-list".stat
            if (-not $statList) {
                Write-Warning "No stat data for resource '$($res.FriendlyName)'."
                continue
            }
            # Create a dictionary of stat objects keyed by their statKey.
            $statsByKey = @{}
            foreach ($stat in $statList) {
                $k = $stat."statKey".key
                $statsByKey[$k] = $stat
            }
            # Assume all stat objects share the same timestamps.
            $timestamps = $statList[0].timestamps
            for ($i = 0; $i -lt $timestamps.Count; $i++) {
                $ts = (Get-Date "1970-01-01T00:00:00Z").AddMilliseconds($timestamps[$i])
                $row = [PSCustomObject]@{
                    ObjectName = $res.FriendlyName
                    Timestamp  = $ts
                }
                foreach ($requestedKey in $statKeys) {
                    if ($statsByKey.ContainsKey($requestedKey)) {
                        $row | Add-Member -NotePropertyName $requestedKey -NotePropertyValue $statsByKey[$requestedKey].data[$i]
                    }
                    else {
                        $row | Add-Member -NotePropertyName $requestedKey -NotePropertyValue $null
                    }
                }
                $results += $row
            }
        }
        else {
            Write-Warning "No data returned for resource '$($res.FriendlyName)' (ID: $($res.ResourceId))."
            # Optionally, output a row with null metric values.
        }
    }
    $outputFile = Join-Path $OutputDirectory ("{0}_metrics.csv" -f $resourceKind)
    Write-Output "Exporting results for resource kind '$resourceKind' to $outputFile"
    $results | Export-Csv -Path $outputFile -NoTypeInformation
}
#endregion
