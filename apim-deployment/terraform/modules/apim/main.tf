resource "azurerm_api_management" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.sku_name
  zones               = length(var.zones) > 0 ? var.zones : null
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# Global policy (applies at the service scope). Only created when a file path
# is provided and the file exists on disk.
resource "azurerm_api_management_policy" "global" {
  count = var.global_policy_xml_path != "" && fileexists(var.global_policy_xml_path) ? 1 : 0

  api_management_id = azurerm_api_management.this.id
  xml_content       = file(var.global_policy_xml_path)
}
