add-type @"
   using System.Net;
   using System.Security.Cryptography.X509Certificates;
   public class TrustAllCertsPolicy : ICertificatePolicy {
      public bool CheckValidationResult(
      ServicePoint srvPoint, X509Certificate certificate,
      WebRequest request, int certificateProblem) {
      return true;
   }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$vROPSFQDN = "vrops.lab.sentania.net"
$vROPSuser = "admin"
$vROPSpasswd = "VMware1!!"
$reportName = "Capacity Report - Virtual Machines"
$reportTargetName = "vSphere World"


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
#region Pull list of all existing groups
$reportdefinitionList = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/reportdefinitions?name=$reportname" -Method 'GET' -Headers $secHeaders
$reportID = $reportdefinitionList.reportDefinitions.id

$reportTarget = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/resources?name=$reportTargetName" -Method 'GET' -Headers $secHeaders
$reportTargetID = $reportTarget.resourcelist.identifier

$reportGenBody = "{
    `n  `"reportDefinitionId`” : `”$reportID`”,
    `n  `"resourceId`” : `”$reportTargetID`”
    `n}”
$generatedReport = Invoke-RestMethod "https://$vROPSFQDN/suite-api/api/reports" -Method 'POST' -Headers $secHeaders -Body $reportGenBody

$generatedReportID = $generatedReport.id