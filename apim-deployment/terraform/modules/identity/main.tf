resource "azurerm_api_management_identity_provider_aad" "this" {
  for_each = { for k, v in var.identity_providers : k => v if v.type == "aad" }

  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  client_id           = each.value.client_id
  client_secret       = each.value.client_secret
  allowed_tenants     = each.value.allowed_tenants
  signin_tenant       = each.value.signin_tenant
}

resource "azurerm_api_management_group" "this" {
  for_each = var.groups

  name                = each.key
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  display_name        = each.value.display_name
  description         = each.value.description
  type                = each.value.type
}

resource "azurerm_api_management_user" "this" {
  for_each = var.users

  user_id             = each.key
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  first_name          = each.value.first_name
  last_name           = each.value.last_name
  email               = each.value.email
  state               = each.value.state
  note                = each.value.note
}
