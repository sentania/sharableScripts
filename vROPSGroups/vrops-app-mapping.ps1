# Creates "(Custom) Application" groups (VMs by vSphere tag) and "(Custom) Porfolio" groups
# (Application groups by name suffix) in VCF Operations / Aria Operations. Safe to re-run.
# Tested on Aria Ops 8.18.7, VCF Ops 9.0.2 and 9.1.1. Needs PowerShell 7.
# Usage: ./vrops-app-mapping.ps1 -vROPSFQDN ops.example.com [-Credential (Get-Credential)] [-SkipCertificateCheck]
#        or set OPS_FQDN, OPS_USER, OPS_PASS in the environment.
param(
    [string]$vROPSFQDN = $env:OPS_FQDN,
    [pscredential]$Credential,
    [string]$AuthSource = "local",
    [switch]$SkipCertificateCheck
)
$ErrorActionPreference = "Stop"
$applicationTags = import-csv .\app-mapping.csv
###expected format:  groupname, grouptag, grouptagcatagory (spelled as in the CSV header)
$portfolioApplicationMappings = import-csv .\portfolio-app-mapping.csv
###expected format: groupname, porfolioCode
if (-not $Credential) {
    if ($env:OPS_USER -and $env:OPS_PASS) {
        $Credential = [pscredential]::new($env:OPS_USER, (ConvertTo-SecureString $env:OPS_PASS -AsPlainText -Force))
    } else { $Credential = Get-Credential -Message "Ops user for $vROPSFQDN" }
}
$PSDefaultParameterValues['Invoke-RestMethod:SkipCertificateCheck'] = [bool]$SkipCertificateCheck
$PSDefaultParameterValues['Invoke-RestMethod:ContentType'] = 'application/json; charset=utf-8'


$applicationGroupTYpe = "(Custom) Application"
$portfolioGroupType = "(Custom) Porfolio"

#region AUTHENTICATE TO vROPS
$firstBody = @{
    username   = $Credential.UserName
    password   = $Credential.GetNetworkCredential().Password
    authSource = $AuthSource
} | ConvertTo-Json

$firstResponse = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/auth/token/acquire" -Method 'POST' -Headers @{ Accept = "application/json" } -Body $firstBody

#We get the token. (not printed: it is a live bearer credential)

$token = $firstResponse.token
$secHeaders = @{ Accept = "application/json"; Authorization = "OpsToken $token" }

#endregion

#region make sure both custom group types exist (key = name when created this way)
$existingTypes = (Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/resources/groups/types" -Method 'GET' -Headers $secHeaders).groupTypes.key
foreach ($t in @($applicationGroupTYpe, $portfolioGroupType)) {
    if ($existingTypes -notcontains $t) {
        Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/resources/groups/types" -Method 'POST' -Headers $secHeaders -Body (@{ name = $t } | ConvertTo-Json) | Out-Null
        Write-Host "created group type $t"
    }
}
#endregion

#region Pull list of all existing groups
$groupList = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/resources/groups?pageSize=10000" -Method 'GET' -Headers $secHeaders
$existingGroups = @($groupList.groups | ForEach-Object { "$($_.resourceKey.resourceKindKey)|$($_.resourceKey.name)" })

#endregion
#for each application in our input file we will create a group of the
foreach ($applicationTag in $applicationTags)
{
$groupName = $applicationTag.groupname
$grouptag = $applicationTag.grouptag
$groupcategory =  $applicationtag.grouptagcatagory

#if the group exists - don't create it
if ($existingGroups -contains "$applicationGroupTYpe|$groupName")
{
    Write-Host "exists: $groupName"
    continue
}
$secBody = @{
    resourceKey = @{ name = $groupName; adapterKindKey = "Container"; resourceKindKey = $applicationGroupTYpe }
    autoResolveMembership = $true
    membershipDefinition = @{ rules = @(@{
        resourceKindKey = @{ resourceKind = "VirtualMachine"; adapterKind = "VMWARE" }
        resourceTagConditionRules = @(@{ category = $groupcategory; compareOperator = "EQ"; stringValue = $grouptag })
    }) }
} | ConvertTo-Json -Depth 10

try {
    $secResponse = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/resources/groups" -Method 'POST' -Headers $secHeaders -Body $secBody
    Write-Host "created: $groupName"
} catch { Write-Warning "failed: $groupName : $($_.ErrorDetails.Message)" }
}

foreach ($portfolioApplicationMapping in $portfolioApplicationMappings)
{
$groupName = $portfolioApplicationMapping.groupname
$portfoliocode = $portfolioApplicationMapping.portfoliocode

if ($existingGroups -contains "$portfolioGroupType|$groupName")
{
    Write-Host "exists: $groupName"
    continue
}
# match app groups whose name ENDS with " <code>"; CONTAINS "Lab" also hits every "LabAppN ..." name
$secBody = @{
    resourceKey = @{ name = $groupName; adapterKindKey = "Container"; resourceKindKey = $portfolioGroupType }
    autoResolveMembership = $true
    membershipDefinition = @{ rules = @(@{
        resourceKindKey = @{ resourceKind = $applicationGroupTYpe; adapterKind = "Container" }
        resourceNameConditionRules = @(@{ name = " $portfoliocode"; compareOperator = "ENDS_WITH" })
    }) }
} | ConvertTo-Json -Depth 10

try {
    $secResponse = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/resources/groups" -Method 'POST' -Headers $secHeaders -Body $secBody
    Write-Host "created: $groupName"
} catch { Write-Warning "failed: $groupName : $($_.ErrorDetails.Message)" }
}
