variable "apim_id" {
  description = "ARM resource ID of the APIM service (parent for the MCP APIs)."
  type        = string
}

variable "source_api_ids" {
  description = "Map of source-API logical name -> ARM resource ID. Used to construct mcpTools[].operationId values."
  type        = map(string)
}

variable "mcp_servers" {
  description = <<-EOT
    Map of MCP servers to expose. Each entry creates a separate APIM API of
    type=mcp whose tools delegate to operations of an existing source API.

    The MCP endpoint URL is: https://<apim>.azure-api.net/<path>/mcp
  EOT
  type = map(object({
    display_name          = string
    description           = optional(string, "")
    path                  = string
    protocols             = optional(list(string), ["https"])
    subscription_required = optional(bool, true)
    tools = list(object({
      name             = string
      description      = string
      source_api_name  = string
      source_operation = string
    }))
  }))
  default = {}

  validation {
    condition = alltrue([
      for srv in var.mcp_servers :
      length(srv.tools) > 0
    ])
    error_message = "Each MCP server must declare at least one tool."
  }
}
