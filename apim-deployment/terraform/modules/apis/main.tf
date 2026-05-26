locals {
  # Flatten { api_key -> { op_id -> path } } into a list for_each can iterate over.
  operation_policies = merge([
    for api_key, api in var.apis : {
      for op_id, policy_path in api.operation_policies :
      "${api_key}.${op_id}" => {
        api_key     = api_key
        operation   = op_id
        policy_path = policy_path
      }
    }
  ]...)
}

resource "azurerm_api_management_api" "this" {
  for_each = var.apis

  name                = each.key
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  revision            = "1"
  display_name        = each.value.display_name
  path                = each.value.path
  protocols           = each.value.protocols

  import {
    content_format = endswith(lower(each.value.openapi_path), ".yaml") || endswith(lower(each.value.openapi_path), ".yml") ? "openapi" : "openapi+json"
    content_value  = file(each.value.openapi_path)
  }
}

# API-scoped policies (per API).
resource "azurerm_api_management_api_policy" "this" {
  for_each = {
    for k, v in var.apis :
    k => v if try(v.api_policy_xml_path, "") != "" && fileexists(try(v.api_policy_xml_path, ""))
  }

  api_name            = azurerm_api_management_api.this[each.key].name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  xml_content         = file(each.value.api_policy_xml_path)
}

# Operation-scoped policies.
resource "azurerm_api_management_api_operation_policy" "this" {
  for_each = local.operation_policies

  api_name            = azurerm_api_management_api.this[each.value.api_key].name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  operation_id        = each.value.operation
  xml_content         = file(each.value.policy_path)
}
