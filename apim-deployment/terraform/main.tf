resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

module "apim" {
  source = "./modules/apim"

  name                   = var.apim_name
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  sku_name               = var.apim_sku
  zones                  = var.apim_zones
  publisher_name         = var.publisher_name
  publisher_email        = var.publisher_email
  global_policy_xml_path = var.global_policy_xml_path
  tags                   = local.common_tags
}

module "named_values_backends" {
  source = "./modules/named-values-backends"

  apim_name           = module.apim.name
  resource_group_name = azurerm_resource_group.this.name

  named_values = var.named_values
  backends     = var.backends
}

module "apis" {
  source = "./modules/apis"

  apim_name           = module.apim.name
  resource_group_name = azurerm_resource_group.this.name

  apis = var.apis

  depends_on = [module.named_values_backends]
}

module "products" {
  source = "./modules/products"

  apim_name           = module.apim.name
  resource_group_name = azurerm_resource_group.this.name

  products      = var.products
  subscriptions = var.subscriptions

  depends_on = [module.apis]
}

module "mcp" {
  source = "./modules/mcp"

  apim_id        = module.apim.id
  source_api_ids = module.apis.api_ids
  mcp_servers    = var.mcp_servers

  depends_on = [module.apis]
}

module "identity" {
  source = "./modules/identity"

  apim_name           = module.apim.name
  resource_group_name = azurerm_resource_group.this.name

  identity_providers = var.identity_providers
  users              = var.users
  groups             = var.groups
}
