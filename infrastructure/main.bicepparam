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
param startDate = '2026-09-01T00:00:00Z'
param endDate = '2030-05-31T00:00:00Z'
