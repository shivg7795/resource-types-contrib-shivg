
// ---------------------------------------------------------------------------
// Radius Azure ACI Key Vault Secrets Recipe
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('The Radius resource context object containing resource properties and metadata.')
param context object

@description('Azure region for new resources. Defaults to the resource group location.')
param location string = resourceGroup().location

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

// Names derived from the Radius resource name to keep deployments deterministic.
var keyVaultName = 'kv-${context.resource.name}'
var identityName = context.resource.name

// Secret data sourced entirely from the Radius context object – not hardcoded.
var secretData = context.resource.properties.data

// Flatten the map into an array suitable for Bicep resource loops.
var secretItems = [for item in items(secretData): {
  name: item.key
  value: item.value.value
}]

// Built-in role: Key Vault Administrator – grants full access to all Key Vault data-plane operations.
var keyVaultAdministratorRoleId = '00482a5a-887f-4fb3-b363-3b7fe8e74483'

// Deterministic GUID for the role assignment prevents redeploy churn.
var roleAssignmentName = guid(keyVault.id, uai.id, keyVaultAdministratorRoleId)

// ---------------------------------------------------------------------------
// Key Vault
// ---------------------------------------------------------------------------
// Creates a new vault in the same resource group as the recipe deployment.
// RBAC authorization is enabled so role assignments (not access policies)
// govern data-plane access.

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: {
    'radius-resource': context.resource.name
    'radius-application': context.application == null ? '' : context.application.name
  }
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
  }
}

// ---------------------------------------------------------------------------
// User Assigned Managed Identity
// ---------------------------------------------------------------------------


resource uai 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: {
    'radius-resource': context.resource.name
    'radius-application': context.application == null ? '' : context.application.name
  }
}

// ---------------------------------------------------------------------------
// RBAC – Key Vault Administrator role assignment
// ---------------------------------------------------------------------------
// Grants the UAI the "Key Vault Administrator" role (full data-plane access)
// scoped to this Key Vault only.

resource kvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  scope: keyVault
  properties: {
    principalId: uai.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultAdministratorRoleId)
  }
}

// ---------------------------------------------------------------------------
// Write secrets into Key Vault
// ---------------------------------------------------------------------------
// Iterates over context.resource.properties.data and creates/updates a
// Key Vault secret for each entry. 

resource kvSecrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [for secret in secretItems: {
  name: secret.name
  parent: keyVault
  properties: {
    value: secret.value
    contentType: 'text/plain'
  }
}]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the created Azure Key Vault.')
output keyVaultId string = keyVault.id

@description('Resource ID of the User Assigned Managed Identity.')
output userAssignedIdentityId string = uai.id

@description('Client ID of the User Assigned Managed Identity (used in application code).')
output userAssignedIdentityClientId string = uai.properties.clientId

@description('Principal (object) ID of the User Assigned Managed Identity.')
output userAssignedIdentityPrincipalId string = uai.properties.principalId

// Radius recipe result 
// The UAI resource ID is included so the Radius CP can track it and
// downstream ACI container recipes can reference it for identity assignment.
output result object = {
  resources: [
    uai.id
  ]
}

