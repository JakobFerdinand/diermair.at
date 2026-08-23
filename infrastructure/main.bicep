targetScope = 'resourceGroup'

@description('Name of the existing static web app.')
param staticSiteName string

@description('Region of the static web app.')
param location string

@description('Custom domains for the static web app.')
param customDomains array = []

@description('Email address used for budget notifications (non-secret configuration).')
param budgetNotificationEmail string

@description('Action group notified on budget threshold breach.')
param actionGroupName string = 'diermairat-budget-actions'

@description('Name of the storage account for website analytics.')
param storageAccountName string

module storage './modules/storage.bicep' = {
  name: 'storage'
  params: {
    storageAccountName: storageAccountName
    location: location
  }
}

module staticSites './modules/static-sites.bicep' = {
  name: 'staticSites'
  params: {
    siteName: staticSiteName
    location: location
    customDomains: customDomains
  }
}

resource budgetActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  properties: {
    enabled: true
    groupShortName: 'diermairat'
    emailReceivers: [
      {
        name: 'budget-notifications'
        emailAddress: budgetNotificationEmail
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
  }
}
