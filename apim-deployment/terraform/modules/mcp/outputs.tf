output "mcp_api_ids" {
  description = "Map of MCP server key -> ARM resource ID."
  value       = { for k, r in azapi_resource.mcp_api : k => r.id }
}

output "mcp_endpoint_paths" {
  description = "Map of MCP server key -> URL path suffix (append to APIM gateway URL to get the full MCP endpoint URL)."
  value       = { for k, srv in var.mcp_servers : k => "${srv.path}/mcp" }
}
