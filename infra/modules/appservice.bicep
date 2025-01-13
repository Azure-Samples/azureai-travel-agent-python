param location string
param vnetLocation string = location
param appServicePlanName string
param appServiceName string
param msiID string
param msiClientID string
param sku string = 'P0v3'
param tags object = {}
param deploymentName string

param aiServicesName string
param bingName string
param cosmosName string
param aiHubName string
param aiProjectName string
param keyVaultName string

param authMode string
param publicNetworkAccess string
param privateEndpointSubnetId string
param appSubnetId string
param privateDnsZoneId string
param allowedIpAddresses array = []

var allowedIpRestrictions = [
  for allowedIpAddressesArray in allowedIpAddresses: {
    ipAddress: '${allowedIpAddressesArray}/32'
    action: 'Allow'
    priority: 300
  }
]

var ipSecurityRestrictions = concat(allowedIpRestrictions, [
  { action: 'Allow', ipAddress: 'AzureBotService', priority: 100, tag: 'ServiceTag' }
  // Allow Teams Messaging IPs
  { action: 'Allow', ipAddress: '13.107.64.0/18', priority: 200 }
  { action: 'Allow', ipAddress: '52.112.0.0/14', priority: 201 }
  { action: 'Allow', ipAddress: '52.120.0.0/14', priority: 202 }
  { action: 'Allow', ipAddress: '52.238.119.141/32', priority: 203 }
])

resource aiServices 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: aiServicesName
}

resource aiProject 'Microsoft.MachineLearningServices/workspaces@2024-04-01-preview' existing = {
  name: aiProjectName
}

resource bingAccount 'Microsoft.Bing/accounts@2020-06-10' existing = {
  name: bingName
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: cosmosName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: sku
    capacity: 1
  }
  properties: {
    reserved: true
  }
  kind: 'linux'
}

resource backend 'Microsoft.Web/sites@2023-12-01' = {
  name: appServiceName
  location: location
  tags: union(tags, { 'azd-service-name': 'azure-agents-app' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${msiID}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    virtualNetworkSubnetId: !empty(appSubnetId) ? appSubnetId : null
    keyVaultReferenceIdentity: msiID
    vnetRouteAllEnabled: true
    siteConfig: {
      keyVaultReferenceIdentity: msiID
      vnetRouteAllEnabled: true
      httpLoggingEnabled: true
      logsDirectorySizeLimit: 35
      ipSecurityRestrictions: ipSecurityRestrictions
      publicNetworkAccess: 'Enabled'
      ipSecurityRestrictionsDefaultAction: 'Allow'
      scmIpSecurityRestrictionsDefaultAction: 'Allow'
      http20Enabled: true
      linuxFxVersion: 'PYTHON|3.10'
      webSocketsEnabled: true
      appCommandLine: 'gunicorn app:app'
      alwaysOn: true
      appSettings: [
        {
          name: 'MicrosoftAppType'
          value: 'UserAssignedMSI'
        }
        {
          name: 'MicrosoftAppId'
          value: msiClientID
        }
        {
          name: 'MicrosoftAppTenantId'
          value: tenant().tenantId
        }
        {
          name: 'AZURE_AI_PROJECT_CONNECTION_STRING'
          value: '${split(aiProject.properties.discoveryUrl, '/')[2]};${subscription().subscriptionId};${resourceGroup().name};${aiProjectName}'
        }
        {
          name: 'SSO_ENABLED'
          value: 'false'
        }
        {
          name: 'SSO_CONFIG_NAME'
          value: ''
        }
        {
          name: 'SSO_MESSAGE_TITLE'
          value: 'Please sign in to continue.'
        }
        {
          name: 'SSO_MESSAGE_PROMPT'
          value: 'Sign in'
        }
        {
          name: 'SSO_MESSAGE_SUCCESS'
          value: 'User logged in successfully! Please repeat your question.'
        }
        {
          name: 'SSO_MESSAGE_FAILED'
          value: 'Log in failed. Type anything to retry.'
        }
        {
          name: 'AZURE_OPENAI_API_ENDPOINT'
          value: aiServices.properties.endpoint
        }
        {
          name: 'AZURE_OPENAI_API_VERSION'
          value: '2024-05-01-preview'
        }
        {
          name: 'AZURE_OPENAI_DEPLOYMENT_NAME'
          value: deploymentName
        }
        {
          name: 'AZURE_OPENAI_ASSISTANT_ID'
          value: 'YOUR_ASSISTANT_ID'
        }
        {
          name: 'AZURE_OPENAI_STREAMING'
          value: 'true'
        }
        {
          name: 'AZURE_OPENAI_API_KEY'
          value: authMode == 'accessKey' ? aiServices.listKeys().key1 : ''
        }
        {
          name: 'AZURE_BING_API_ENDPOINT'
          value: 'https://api.bing.microsoft.com/'
        }
        {
          name: 'AZURE_BING_API_KEY'
          value: bingAccount.listKeys().key1
        }
        {
          name: 'AZURE_COSMOSDB_ENDPOINT'
          value: cosmos.properties.documentEndpoint
        }
        {
          name: 'AZURE_COSMOSDB_DATABASE_ID'
          value: 'GenAIBot'
        }
        {
          name: 'AZURE_COSMOSDB_CONTAINER_ID'
          value: 'Conversations'
        }
        {
          name: 'AZURE_COSMOS_AUTH_KEY'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=AZURE-COSMOS-AUTH-KEY)'
        }
        {
          name: 'AZURE_DIRECT_LINE_SECRET'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=AZURE-DIRECT-LINE-SECRET)'
        }
        {
          name: 'MAX_TURNS'
          value: '10'
        }
        {
          name: 'LLM_WELCOME_MESSAGE'
          value: 'Welcome to the Travel Agent Sample! You can use this chat to: <br>&ensp;- Get recommendations of places to visit and things to do;<br>&ensp;- Upload your travel bookings and generate an itinerary;<br>&ensp;- Upload pictures of signs, menus and more to get information about them;<br>&ensp;- Ask for help with budgeting a trip;<br>&ensp;- And more!<br> To upload files, use the attachment button on the left, attach a file and hit enter to upload. You will get confirmation when the file is ready to use. You will also be prompted whether you\'d like to add it to Code Interpreter or File Search. Use Code Interpreter for mathematical operations, and File Search to use the file contents as context for your question. You may skip this step for images.'
        }
        {
          name: 'LLM_INSTRUCTIONS'
          value: 'You are a helpful travel agent who can assist with many travel-related inquiries, including:\n- Reading travel documents and putting together itineraries\n- Viewing and interpreting pictures that may be in different languages\n- Locating landmarks and suggesting places to visit\n- Budgeting and graphing cost information\n- Looking up information on the web for up to date information\nYou should do your best to respond to travel-related questions, but politely decline to help with unrelated questions.\nAny time the information you want to provide requires up-to-date sources - for example, hotels, restaurants and more - you should use the Bing Search tool and provide sources.'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'ENABLE_ORYX_BUILD'
          value: 'true'
        }
        {
          name: 'DEBUG'
          value: 'true'
        }
        {
          name:'AZURE_KEY_VAULT_ENDPOINT'
          value: keyVault.properties.vaultUri
        }
      ]
    }
  }
}

// resource backendAppPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-05-01' = if (publicNetworkAccess == 'Disabled') {
//   name: 'pl-${appServiceName}'
//   location: location
//   tags: tags
//   properties: {
//     subnet: {
//       id: privateEndpointSubnetId
//     }
//     privateLinkServiceConnections: [
//       {
//         name: 'private-endpoint-connection'
//         properties: {
//           privateLinkServiceId: backend.id
//           groupIds: ['sites']
//         }
//       }
//     ]
//   }
//   resource privateDnsZoneGroup 'privateDnsZoneGroups' = {
//     name: 'zg-${appServiceName}'
//     properties: {
//       privateDnsZoneConfigs: [
//         {
//           name: 'default'
//           properties: {
//             privateDnsZoneId: privateDnsZoneId
//           }
//         }
//       ]
//     }
//   }
// }

output backendAppName string = backend.name
output backendHostName string = backend.properties.defaultHostName
