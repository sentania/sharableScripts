
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
    [string]$vCenterList,
    
    [Parameter(Mandatory = $true)]
    [string]$vCenterCredID
)
if ($ignoreSSL = $true)
{
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}

#region Read input file
# Read vCenter endpoints from file
$vcenters = Get-Content -Path $vCenterList

#endregion

#region Define Endpoints
$adapterEndpoint = "https://$vROPSFQDN/suite-api/api/adapters"
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

#Get all vcenter adapter instances
$url = $adapterEndpoint + "?_no_links=true"
$allAdaptersResults = Invoke-RestMethod $url -Method GET -Headers $secHeaders
$allAdapters = $allAdaptersResults.adapterInstancesInfoDto
foreach ($vc in $vcenters)
{
    Write-host "CHecking to see if adapter instance exists: $vc"

# Search for a match in the adapterInstancesInfoDto
    if ($allAdapters | Where-Object {$_.resourceKey.resourceIdentifiers | Where-Object {$_.identifierType.name -eq "VCURL" -and $_.value -eq $vc}})
    {
        "vCenter $vc exists, skipping"
    }
    else 
    {
        Write-Host "Creating vCenter Adapter Instance for $vc..."

        $payload = @{
        name              = "vCenter Adapter Instance $vc"
        description       = "vCenter Adapter Instance for $vc"
        adapterKindKey    = "VMWARE"
        resourceIdentifiers = @(
            @{ name = "AUTODISCOVERY"; value = "true" },
            @{ name = "PROCESSCHANGEEVENTS"; value = "true" },
            @{ name = "VCURL"; value = "https://$vc/" }
        )
        credential        = @{ id = $vCenterCredID }
    } | ConvertTo-Json -Depth 5
    $url = $adapterEndpoint + "?extractIdentifierDefaults=false&force=true&_no_links=true"
    $createAdapterInstance = Invoke-RestMethod -Method Post -Uri "$url" -Headers $secHeaders -ContentType "application/json" -Body $payload

    #accept the certificate
    $thumbprint = $createAdapterInstance."adapter-certificates"

   

    #start adapter instance
    $url = $adapterEndpoint + "/" + $createAdapterInstance.id + "/monitoringstate/start?_no_links=true"
    $startAdapterInstance = Invoke-RestMethod -Method PUT -Uri "$url" -Headers $secHeaders 
    }
}