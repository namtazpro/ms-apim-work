resource "azurerm_api_management_named_value" "this" {
  for_each = var.named_values

  name                = each.key
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  display_name        = each.value.display_name
  secret              = each.value.secret
  tags                = each.value.tags

  # Inline value (only when no Key Vault reference is provided).
  value = each.value.key_vault_secret_id == null ? each.value.value : null

  # Key Vault reference (when provided). APIM uses its system-assigned managed
  # identity to read the secret; the identity must have the
  # `Key Vault Secrets User` role on the vault.
  dynamic "value_from_key_vault" {
    for_each = each.value.key_vault_secret_id != null ? [each.value.key_vault_secret_id] : []
    content {
      secret_id = value_from_key_vault.value
    }
  }
}

resource "azurerm_api_management_backend" "this" {
  for_each = var.backends

  name                = each.key
  api_management_name = var.apim_name
  resource_group_name = var.resource_group_name
  protocol            = each.value.protocol
  url                 = each.value.url
}
