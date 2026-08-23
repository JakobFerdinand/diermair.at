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

@description('Name of the cost budget.')
param budgetName string = 'Diermairat-Budget'

@description('Monthly budget amount in EUR.')
param amount int = 3

@description('Budget start date (ISO 8601).')
param startDate string

@description('Budget end date (ISO 8601).')
param endDate string

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

var budgetNotifications = {
  actual_GreaterThan_20_Percent: {
    enabled: true
    operator: 'GreaterThan'
    threshold: 20
    contactGroups: [
      budgetActionGroup.id
    ]
    contactEmails: []
    contactRoles: []
  }
  actual_GreaterThan_80_Percent: {
    enabled: true
    operator: 'GreaterThan'
    threshold: 80
    contactGroups: [
      budgetActionGroup.id
    ]
    contactEmails: []
    contactRoles: []
  }
  actual_GreaterThan_100_Percent: {
    enabled: true
    operator: 'GreaterThan'
    threshold: 100
    contactGroups: [
      budgetActionGroup.id
    ]
    contactEmails: []
    contactRoles: []
  }
}

resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: budgetName
  properties: {
    category: 'Cost'
    amount: amount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
      endDate: endDate
    }
    notifications: budgetNotifications
  }
}

output budgetId string = budget.id
