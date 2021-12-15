#################################################################

 # First Part : Get tags from vCenter changin variable $category #

 #################################################################

 # Note : Get-Tags part are from https://code.vmware.com/samples/2808/automated-custom-group-creation-in-vrops-as-per-vcenter-tags#

 # However creating custom group part was not working as expected. So I wrote new powershell script.

  $Server = Connect-VIServer -Server “####VCENTER SERVER” -User “#####USERNAME” -Password “####PASSWORD#######!”

  #Change Tag Category according to your needs.

  $category = “protection”

  # Retrieve all tags of the category

   if($category){

        $tagList = Get-Tag -Server $Server -Category $category -Verbose | Select Name, Category

    }

    else{

        $tagList = Get-Tag -Server $Server | Select Name, Category

    }

    $tags = @()

    Foreach($item in $tagList){

    $tag = New-Object PSObject

    #This one is important. We’ll use tag name while creating custom groups.

    $tag | add-member -type NoteProperty -Name tagName -Value $item.Name

    #Below part can be uncommented if you want. It just gets tag category.

    #$tag | add-member -type NoteProperty -Name categoryName -Value $item.Category.Name

    $tags += $tag

    }
    write-host $tags -ForegroundColor Red

#################################################################

# Second Part : Get Authorization token from vROps API

#################################################################

$firstHeaders = New-Object “System.Collections.Generic.Dictionary[[String],[String]]”

$firstHeaders.Add(“Content-Type”, “application/json; utf-8”)

$firstHeaders.Add(“Accept”, “application/json”)

#Enter your username and password. I just tried with local user.

$firstBody = “{

`n  `”username`” : `”####VROPS LOCAL USER`”,

`n  `”password`” : `”####VROPS PASSWORD!`”,

`n  `”others`” : [ ],

`n  `”otherAttributes`” : { }

`n}”

#Enter your vROps IP or FQDN

$firstResponse = Invoke-RestMethod ‘https://vrops.lab.sentania.net/suite-api/api/auth/token/acquire' -Method ‘POST’ -Headers $firstHeaders -Body $firstBody

$firstResponse | ConvertTo-Json

#We get the token.

$token = $firstResponse.token

#################################################################

# Third Part : Create custom groups using vROps API

#################################################################

# $key is the Tag Category again.

$key = “protection”

#Below for loop will create custom group for each tag name in tag category. For our example, it “Environment”

foreach ($tag in $tags)
{

#Check 70th line. This will get tags step by step. And we’ll use them in request body.

#Check 80th line. Tag Name will be group Name.

#Check 81st line. This is Container for custom groups. Do not change it!

#Check 82nd line. This is the group type. Change it according to your needs!

$tagName = $tag.tagName

$secHeaders = New-Object “System.Collections.Generic.Dictionary[[String],[String]]”

$secHeaders.Add(“Content-Type”, “application/json; utf-8”)

$secHeaders.Add(“Accept”, “application/json”)

$secHeaders.Add(“Authorization”, “vRealizeOpsToken $token”)

$secBody = “{
 ""resourceKey"": {
        ""name`": ""$category-$tagName"",
        ""adapterKindKey"": ""Container"",
        ""resourceKindKey"": ""Environment"" 
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
                   ""category"" : ""$category"",
                   ""compareOperator"" : ""EQ"",
                   ""stringValue"" : ""$tagName""
            }
        ]
}]
}
}”
write-host -ForegroundColor Yellow $secBody
$secResponse = Invoke-RestMethod ‘https://vrops.lab.sentania.net/suite-api/api/resources/groups' -Method ‘POST’ -Headers $secHeaders -Body $secBody

}