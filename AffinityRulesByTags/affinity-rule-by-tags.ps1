param (
    [Parameter(Mandatory=$true)][string[]]$vcenterlist,
    [Parameter(Mandatory=$true)][string]$vCUsername,
    [Parameter(Mandatory=$true)][string]$vcPassword,
    [Parameter(Mandatory=$true)][string[]]$tagcategories
)
#$cred = Get-Credential
#$vcenterlist = "lab-comp01-vcenter.int.sentania.net"
#$tagcategories = "businessIntent"

###CYCLE THROUGH EACH vCENTER
foreach ($vcenter in $vcenterlist)
{
  $vCConn = Connect-VIServer -Server $vcenter -User $vCUsername -Password $vcPassword
  Write-host "Processing DRS Rules via tags for: $vcenter..."

  ####CYCLE THROUGH EACH TAG CATEGORY
  foreach ($tagCategory in $tagcategories)
  {
    Write-host "Processing tag category: $tagcategory..."
    $tagcategoryObj = Get-TagCategory -Name $tagCategory -server $vCConn
    $tagcategoryObj

    ####cycle through each tag in the category
    $tags = get-tag -Category $tagcategoryObj
    foreach ($tag in $tags)
    {
       Write-host "Processing tag: $tag" -ForegroundColor Yellow
        ###cycle through each cluster for every tag
       $clusters = get-cluster -Server $vCConn
       foreach ($cluster in $clusters)
       {
            Write-host "Processing Cluster: $cluster..."
            

            #get all hosts that have this tag
            $vmhosts = $cluster | get-vmhost -Tag $tag
            $vms = $cluster | get-vm -Tag $tag
            $vmgroupName = "$cluster.affinitygroup.vm."+ $tag.category +"." + $tag.name
            $hostgroupName = "$cluster.affinitygroup.host."+ $tag.category +"." + $tag.name
            $rulename = "$cluster.affinityRule."+ $tag.category +"." + $tag.name
            if (($vms.count -gt 0) -and ($vmhosts.count -gt 0))
            {
                ###add hosts to host group
                if (($hostgroup = Get-DrsClusterGroup -name $hostgroupName -ea SilentlyContinue))
                {
                    Write-host -ForegroundColor Green "Host Group Exists, updating if required..."
                    ###EVALUTE GROUP FOR REMOVED MEMBERS
                    $currentHostMembers = $hostgroupName.member
                    foreach ( $thishost in $currentHostMembers)
                    {
                        $hostMembersToRemove = @()
                        if ($vmhosts -notcontains $thishost) 
                        {
                            
                            $hostMembersToRemove += $thishost
                        }
                    }
                    if ($hostMembersToRemove.length -gt 0)
                    {
                        Write-host -ForegroundColor Red "Hosts have been removed from the group, updating...."   
                        $hostGroup = Set-DrsClusterGroup -DrsClusterGroup $vmgroupName -VMHost $hostMembersToRemove -Remove
                    }
                    ###EVALUTE GROUP FOR MISSING MEMBERS
                    $currentHostMembers = $hostgroup.member
                    foreach ( $thishost in $vmhosts)
                    {
                        $hostMembersToAdd = @()
                        if ($currentHostMembers -notcontains $thishost) 
                        {
                            
                            $hostMembersToAdd += $thishost
                        }
                    }
                    if ($hostMembersToAdd.Length -gt 0)
                    {
                        Write-host -ForegroundColor Red "Hosts are missing from the group, updating...." 
                        $hostGroup = set-DrsClusterGroup -DrsClusterGroup $hostgroup -VMHost $hostMembersToAdd -Add -Confirm:$false
                    }
                    else
                    {
                        Write-host -ForegroundColor Green "Host group membership is up to date"
                    }
                }
                else
                {
                    Write-host -ForegroundColor DarkYellow "Host Group does not exist, creating..."
                    $hostGroup = New-DrsClusterGroup -Name $hostgroupName -VMHost $vmhosts -Cluster $cluster -Confirm:$false
                }
                    
                if (($vmGroup = Get-DrsClusterGroup -name $vmgroupName  -ea SilentlyContinue))
                {
                    Write-host -ForegroundColor Green "VM Group Exists, updating if required..."
                    ####EVALUATE FOR REMOVED MEMBERS 
                    $currentVMMembers = $vmGroup.member
                    foreach ( $vm in $currentVMMembers)
                    {
                        $vmMembersToRemove = @()
                        if ($vms -notcontains $vm) 
                        {
                            $vmMembersToRemove += $vm
                        }
                    }
                    if ($vmMembersToRemove.Length -gt 0)
                    {
                        $vmGroup = Set-DrsClusterGroup -DrsClusterGroup $vmgroupName -vm $vmMembersToRemove -Remove -Confirm:$false
                    }
                    ####EVALUATE FOR MISSING MEMBERS 
                    $currentVMMembers = $vmGroup.member
                    foreach ( $vm in $vms)
                    {
                        $vmMembersToAdd = @()
                        if ($currentVMMembers -notcontains $vm) 
                        {
                            $vmMembersToAdd += $vm
                        }
                    }
                    if ($vmMembersToAdd.Length -gt 0)
                    {
                        $vmGroup = Set-DrsClusterGroup -DrsClusterGroup $vmgroupName -vm $vmMembersToRemove -Add -Confirm:$false
                    }
                    else
                    {
                        Write-host -ForegroundColor Green "VM group membership is up to date"
                    }

                }
                else
                {
                    Write-host -ForegroundColor DarkYellow "VM Group does not exist, creating..."
                    $vmGroup = new-DrsClusterGroup -Name $vmgroupName -VM $vms -Cluster $cluster -Confirm:$false
                }
                
                if (($vmhostRule = Get-DrsVMHostRule -Name $rulename -Cluster $clusters -ea SilentlyContinue))
                {
                    Write-Host -ForegroundColor DarkGray "VM Host rule exists - group updates will automatically cascade..."
                }
                else
                {                   
                    Write-Host -ForegroundColor DarkGray "VM Host RUle does not exist, updating"    
                    $vmhostrule = New-DrsVMHostRule -Name $rulename -Enabled $true -VMGroup $vmGroup -VMHostGroup $hostGroup -Cluster $cluster -Type ShouldRunOn -Confirm:$false
                }
            }
            else 
            {
                ###REMOVE GROUPS NO LONGER TAGGED 
                Write-host "REMOVING UNUSED RULE and GROUPS....."
                if ($vmGroup = Get-DrsClusterGroup -name $vmgroupName -Cluster $cluster -ErrorAction SilentlyContinue)
                {
                    Write-host "REMOVING RULE: $vmgroup"
                    Write-host ""
                    Remove-DrsClusterGroup -DrsClusterGroup $vmGroup -Confirm:$false
                }
                if ($hostGroup = Get-DrsClusterGroup -name $hostgroupName -Cluster $cluster -ErrorAction SilentlyContinue)
                {
                    Write-host "REMOVING RULE: $hostgroup"
                    Write-host ""
                    Remove-DrsClusterGroup -DrsClusterGroup $hostgroup -Confirm:$false
                }
                if ($drsVMHostRule = Get-DrsVMHostRule -name $rulename -Cluster $cluster -ErrorAction SilentlyContinue)
                {
                    Write-host "REMOVING RULE: $drsvmhostrule"
                    Write-host ""
                    Remove-DrsVMHostRule -RunAsync $drsVMHostRule -Confirm:$false
                }

            }
        }
    }
  }

  Disconnect-VIServer -Server $vCConn -Confirm:$false
 }