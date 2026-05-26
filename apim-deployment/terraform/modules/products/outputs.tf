output "product_ids" {
  value = { for k, p in azurerm_api_management_product.this : k => p.id }
}

output "subscription_keys" {
  description = "Primary keys of created subscriptions. Sensitive."
  value       = { for k, s in azurerm_api_management_subscription.this : k => s.primary_key }
  sensitive   = true
}
