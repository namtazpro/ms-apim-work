locals {
  # Flatten product -> api links for for_each.
  product_api_links = merge([
    for product_key, product in var.products : {
      for api_name in product.api_names :
      "${product_key}.${api_name}" => {
        product_key = product_key
        api_name    = api_name
      }
    }
  ]...)
}

resource "azurerm_api_management_product" "this" {
  for_each = var.products

  product_id            = each.key
  api_management_name   = var.apim_name
  resource_group_name   = var.resource_group_name
  display_name          = each.value.display_name
  description           = each.value.description
  subscription_required = each.value.subscription_required
  approval_required     = each.value.subscription_required ? each.value.approval_required : false
  published             = each.value.published
}

resource "azurerm_api_management_product_api" "this" {
  for_each = local.product_api_links

  product_id          = azurerm_api_management_product.this[each.value.product_key].product_id
  api_name            = each.value.api_name
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_api_management_product_policy" "this" {
  for_each = {
    for k, v in var.products :
    k => v if try(v.policy_xml_path, "") != "" && fileexists(try(v.policy_xml_path, ""))
  }

  product_id          = azurerm_api_management_product.this[each.key].product_id
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  xml_content         = file(each.value.policy_xml_path)
}

resource "azurerm_api_management_subscription" "this" {
  for_each = var.subscriptions

  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  display_name        = each.value.display_name
  product_id          = azurerm_api_management_product.this[each.value.product_key].id
  state               = each.value.state
}
