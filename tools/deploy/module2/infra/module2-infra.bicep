// Declare parameters
@description('The unique name for the Azure Storage Account.')
param storageAccountName string = 'opai${uniqueString(resourceGroup().id)}'

@description('The unique name for the Azure Function App.')
param functionAppName string = 'xact-classifier-openai-${uniqueString(resourceGroup().id)}'

// Optional params
@description('The region to deploy the cluster. By default this will use the same region as the resource group.')
param location string = resourceGroup().location

// Declare variables
var storageAccountType = 'Standard_LRS'
var appServicePlanSku = 'S1'

// Create storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  name: 'default'
  parent: storageAccount
}


// Create storage containers
resource classificationContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: 'classification'
  parent: blobService
 
  properties: {
    publicAccess: 'Blob'
  }
}

resource outputContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  name: 'output'
  parent: blobService
  properties: {
    publicAccess: 'Blob'
  }
}

// Create app service plan
resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: '${functionAppName}-plan'
  location: location
  sku: {
    name: appServicePlanSku
    tier: 'Standard'
  }
}

// Create function app
resource functionApp 'Microsoft.Web/sites@2022-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=[account_key];EndpointSuffix=core.windows.net'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
      ]
    }
  }
}

resource systemTopic 'Microsoft.EventGrid/systemTopics@2021-12-01' = {
  name: 'classification'
  location: location
  properties: {
    source: storageAccount.id
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

// Create event grid subscription
resource eventGridSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2021-12-01' = {
  name: 'storage-account-blob-created'
  parent: systemTopic
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: functionApp.id // resourceId('Microsoft.Web/sites', 'xact-classifier-openai-46u75fgxwk4fq')
              }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
      ]
      subjectBeginsWith: '/blobServices/default/containers/classification/'
    }
  }
}



