output "api_ids" {
  value = { for k, api in azurerm_api_management_api.this : k => api.id }
}

output "api_names" {
  value = { for k, api in azurerm_api_management_api.this : k => api.name }
}
