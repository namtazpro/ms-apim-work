output "id" {
  value = azurerm_api_management.this.id
}

output "name" {
  value = azurerm_api_management.this.name
}

output "gateway_url" {
  value = azurerm_api_management.this.gateway_url
}

output "developer_portal_url" {
  value = azurerm_api_management.this.developer_portal_url
}

output "principal_id" {
  description = "System-assigned managed identity object ID."
  value       = try(azurerm_api_management.this.identity[0].principal_id, null)
}
