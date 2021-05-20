
$cred = Get-Credential
$vcenterlist = "lab-comp01-vcenter.int.sentania.net"
$tagcategories = "businessIntent"

###CYCLE THROUGH EACH vCENTER
foreach ($vcenter in $vcenterlist)
{
  $vCConn = Connect-VIServer -Server $vcenter -Credential $cred
  $cisSrv = Connect-CisServer -Server $vcenter -Credential $cred

  ####CYCLE THROUGH EACH TAG CATEGORY
  foreach ($tagCategory in $tagcategories)
  {
    $tagcategoryObj = Get-TagCategory -Name $tagCategory -server $vCConn
    $tagcategoryObj

    ####cycle through each tag in the category
    $tags = get-tag -Category $tagcategoryObj
    foreach ($tag in $tags)
    {
       ###cycle through each cluster for every tag
       $clusters = get-cluster -Server $vCConn
       foreach ($cluster in $clusters)
       {
            #get all hosts that have this tag
            $vmhosts = $cluster | get-vmhost -Tag $tag
            $vms = $cluster | get-vm -Tag $tag
            if (($vms.count -gt 0) -and ($vmhosts.count -gt 0))
            {
                ###add hosts to host group
                $hostgroupName = "$cluster.affinitygroup.host.$tag"
                $hostGroup = New-DrsClusterGroup -Name $hostgroupName -VMHost $vmhosts -Cluster $cluster

                ##get all the VMs that have this tag
                
                $vmgroupName = "$cluster.affinitygroup.vm.$tag"
                $vmGroup = New-DrsClusterGroup -Name $vmgroupName -VM $vms -Cluster $cluster

                $rulename = "$cluster.affinityRule.$tag"
            
                New-DrsVMHostRule -Name $rulename -Enabled $true -VMGroup $vmGroup -VMHostGroup $hostGroup -Cluster $cluster -Type ShouldRunOn
            }
        }
    }
}













  

}
