output "named_value_ids" {
  value = { for k, n in azurerm_api_management_named_value.this : k => n.id }
}

output "backend_ids" {
  value = { for k, b in azurerm_api_management_backend.this : k => b.id }
}
