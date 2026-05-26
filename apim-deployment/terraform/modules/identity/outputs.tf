output "group_ids" {
  value = { for k, g in azurerm_api_management_group.this : k => g.id }
}

output "user_ids" {
  value = { for k, u in azurerm_api_management_user.this : k => u.id }
}
