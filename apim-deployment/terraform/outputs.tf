output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "apim_name" {
  value = module.apim.name
}

output "apim_gateway_url" {
  value = module.apim.gateway_url
}

output "apim_developer_portal_url" {
  value = module.apim.developer_portal_url
}

output "apim_principal_id" {
  description = "Object ID of the APIM system-assigned managed identity."
  value       = module.apim.principal_id
}
