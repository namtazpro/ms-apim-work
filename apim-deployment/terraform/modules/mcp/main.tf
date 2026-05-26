terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
    }
  }
}

# MCP-type API. azurerm provider does not yet model `type = mcp` or `mcpTools`,
# so we use azapi with the 2025-09-01-preview ARM API.
#
# Discovery notes (see /memories/repo/apim-deployment.md):
#  - `properties.type = "mcp"` is the discriminator.
#  - `properties.mcpTools[]` is an INLINE array on the API (NOT the
#    `mcpProperties.tools` field hinted at by TypeSpec, NOT child
#    `/tools/{id}` resources).
#  - `operationId` MUST be the full ARM resource ID of the source operation,
#    WITHOUT the `;rev=N` revision suffix that azurerm appends to api IDs.
locals {
  # Strip the `;rev=N` revision suffix that azurerm includes in API IDs.
  source_api_ids_clean = {
    for k, id in var.source_api_ids :
    k => replace(id, "/;rev=\\d+/", "")
  }
}

resource "azapi_resource" "mcp_api" {
  for_each = var.mcp_servers

  type      = "Microsoft.ApiManagement/service/apis@2025-09-01-preview"
  name      = each.key
  parent_id = var.apim_id

  body = {
    properties = {
      displayName          = each.value.display_name
      description          = each.value.description
      path                 = each.value.path
      type                 = "mcp"
      protocols            = each.value.protocols
      subscriptionRequired = each.value.subscription_required
      mcpTools = [
        for t in each.value.tools : {
          name        = t.name
          description = t.description
          operationId = "${local.source_api_ids_clean[t.source_api_name]}/operations/${t.source_operation}"
        }
      ]
    }
  }

  # ARM API for MCP is in preview; azapi schema validation is overly strict.
  schema_validation_enabled = false

  response_export_values = ["properties.type", "properties.mcpTools"]
}
