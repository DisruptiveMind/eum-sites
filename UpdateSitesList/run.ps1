﻿[string]$DistributionFolder = $Env:distributionFolder

if ($DistributionFolder -eq "")
{
    $DistributionFolder = (Split-Path $MyInvocation.MyCommand.Path)
    $DistributionFolderArray = $DistributionFolder.Split('\')
    $DistributionFolderArray[$DistributionFolderArray.Count - 1] = ""
    $DistributionFolder = $DistributionFolderArray -join "\"
}

. $DistributionFolder\EUMSites_Helper.ps1
LoadEnvironmentSettings

Helper-Connect-PnPOnline -Url $SitesListSiteURL

# get all sites in the list that have Site Created set
$siteCollectionListItems = Get-PnPListItem -List $SiteListName -Query "
<View>
    <Query>
        <Where>
            <IsNotNull>
                <FieldRef Name='EUMSiteCreated'/>
            </IsNotNull>
        </Where>
    </Query>
    <ViewFields>
        <FieldRef Name='ID'></FieldRef>
        <FieldRef Name='Title'></FieldRef>
        <FieldRef Name='EUMSiteURL'></FieldRef>
        <FieldRef Name='EUMSetComposedLook'></FieldRef>
        <FieldRef Name='EUMBrandingDeploymentType'></FieldRef>
        <FieldRef Name='EUMBreadcrumbHTML'></FieldRef>
        <FieldRef Name='EUMParentURL'></FieldRef>
        <FieldRef Name='EUMSiteTemplate'></FieldRef>
    </ViewFields>
</View>"

# -----------------------------------------
# 1. Delete all sites that no longer exist
# -----------------------------------------
Write-Output "Checking $($SiteListName) for deleted sites. Please wait..."
$siteCollectionListItems | ForEach {
    if (-not(CheckIfSiteExists -siteURL $_["EUMSiteURL"].Url -disconnect))
    {
        Write-Output "$($_["Title"]), URL:$($_["EUMSiteURL"].Url) does not exist. Deleting from list..."
        Helper-Connect-PnPOnline -Url $SitesListSiteURL
        Remove-PnPListItem -List $SiteListName -Identity $_.Id -Force
    }
}

# -------------------------------------------
# 2. Update existing entries
# -------------------------------------------
Write-Output "Updating existing entries in $($SiteListName). Please wait..."
Helper-Connect-PnPOnline -Url $SitesListSiteURL
$siteCollectionListItems = Get-PnPListItem -List $SiteListName -Query "
<View>
    <Query>
        <Where>
            <And>
                <IsNotNull>
                    <FieldRef Name='EUMSiteCreated'/>
                </IsNotNull>
                <Eq>
                    <FieldRef Name='EUMIsSubsite'/>
                    <Value Type='Integer'>0</Value>
                </Eq>
            </And>
        </Where>
        <OrderBy>
            <FieldRef Name='EUMParentURL' Ascending='TRUE' />
        </OrderBy>
    </Query>
    <ViewFields>
        <FieldRef Name='ID'></FieldRef>
        <FieldRef Name='Title'></FieldRef>
        <FieldRef Name='EUMSiteURL'></FieldRef>
        <FieldRef Name='EUMSetComposedLook'></FieldRef>
        <FieldRef Name='EUMBrandingDeploymentType'></FieldRef>
        <FieldRef Name='EUMBreadcrumbHTML'></FieldRef>
        <FieldRef Name='EUMParentURL'></FieldRef>
        <FieldRef Name='EUMSiteTemplate'></FieldRef>
        <FieldRef Name='EUMSiteCreated'></FieldRef>
    </ViewFields>
</View>"
    

$siteCollectionListItems | ForEach {
    [string]$SiteRelativeURL = ($_["EUMSiteURL"].Url).Replace($WebAppURL, "")
    [string]$siteTitle = $_["Title"]
    [string]$parentURL = $_["EUMParentURL"].Url
    [string]$parentBreadcrumbHTML = ""

    if ($parentURL)
    {
        $parentURL = $parentURL.Replace($WebAppURL, "")
        $parentListItem = GetSiteEntry -siteRelativeURL $parentURL
        if (-not($parentListItem))
        {
            # parent no longer exists so set to null
            $parentURL = ""
        }
        else
        {
            [string]$parentBreadcrumbHTML = $parentListItem["EUMBreadcrumbHTML"]
        }
    }
    [string]$breadcrumbHTML = GetBreadcrumbHTML -siteRelativeURL $SiteRelativeURL -siteTitle $siteTitle -parentBreadcrumbHTML $parentBreadcrumbHTML

    $spSubWebs = GetSubWebs -siteURL "$($WebAppURL)$($SiteRelativeURL)" -disconnect

	AddOrUpdateSiteEntry -siteRelativeURL $SiteRelativeURL -siteTitle $siteTitle -parentURL $parentURL -breadcrumbHTML $breadcrumbHTML -spSubWebs $spSubWebs    
}
    
# ---------------------------------------------------------
# 3. Iterate through all site collections and add new ones
# ---------------------------------------------------------
Write-Output "Adding tenant site collections to ($SiteListName). Please wait..."
Helper-Connect-PnPOnline -Url $SitesListSiteURL
$siteCollections = Get-PnPTenantSite -IncludeOneDriveSites

$siteCollections | ForEach {
    [string]$SiteRelativeURL = ($_.Url).Replace($WebAppURL, "")
    [string]$siteTitle = $_.Title
    [string]$parentURL = ""

    # Exclude the default site collections
    if (($SiteRelativeURL.ToLower() -notlike "*/portals/community") -and 
        ($SiteRelativeURL.ToLower() -notlike "*/portals/hub") -and 
        ($SiteRelativeURL.ToLower() -notlike "*/sites/contenttypehub") -and 
        ($SiteRelativeURL.ToLower() -notlike "*/search") -and 
        ($SiteRelativeURL.ToLower() -notlike "*/sites/appcatalog") -and 
        ($SiteRelativeURL.ToLower() -notlike "*/sites/compliancepolicycenter") -and 
        ($SiteRelativeURL.ToLower() -notlike "*-my.sharepoint.com*") -and 
        ($SiteRelativeURL.ToLower() -ne "/")) 
        {
            [string]$parentBreadcrumbHTML = ""
            [string]$breadcrumbHTML = GetBreadcrumbHTML -siteRelativeURL $SiteRelativeURL -siteTitle $siteTitle -parentBreadcrumbHTML $parentBreadcrumbHTML

            $spSubWebs = GetSubWebs -siteURL "$($WebAppURL)$($SiteRelativeURL)"
            Helper-Connect-PnPOnline -Url $_.Url
            [Microsoft.SharePoint.Client.Web]$spWeb = Get-PnPWeb -Includes Created
            [DateTime]$siteCreatedDate = $spWeb.Created.Date

	        AddSiteEntry -siteRelativeURL $SiteRelativeURL -siteTitle $siteTitle -parentURL $parentURL -breadcrumbHTML $breadcrumbHTML -spSubWebs $spSubWebs -siteCreatedDate $siteCreatedDate    
        }
}
