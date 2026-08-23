using './main.bicep'

param staticSiteName = 'diermairat'
param location = 'westeurope'
param storageAccountName = 'stdiermairat'
param customDomains = [
  'diermair.at'
  'www.diermair.at'
]
param budgetNotificationEmail = 'j.wegenschimmel@gmail.com'
param actionGroupName = 'diermairat-budget-actions'
