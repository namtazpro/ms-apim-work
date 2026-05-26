---
title: Scripting MCP Configuration on APIM
description: Step-by-step guide to declaratively expose an existing APIM REST API as an MCP server (az CLI, Terraform/azapi, Bicep), with the non-obvious gotchas spelled out
author: Vincent Rouet
ms.date: 2026-05-26
ms.topic: how-to
keywords:
  - apim
  - mcp
  - model-context-protocol
  - terraform
  - azapi
  - bicep
  - arm
---

## Scripting MCP Configuration on APIM

This guide explains how to declaratively expose an existing APIM REST API operation as a tool of an MCP server. It is harder than it looks because most public references for MCP on APIM are either GUI-only or rely on TypeSpec fields that the runtime does not accept.

This doc captures the shape that has been **verified to work** on `Microsoft.ApiManagement/service/apis@2025-09-01-preview` in West Europe, May 2026.

## Why this is not straightforward

Common pitfalls when reading the official material:

* The Azure portal flow uses an undocumented client-side mechanism. Inspecting it suggests fields that look right but do not work for direct ARM callers.
* The TypeSpec for the API points to `properties.mcpProperties.tools` and a child resource `Microsoft.ApiManagement/service/apis/tools`. **Neither works** via PUT in `2025-09-01-preview`; the server silently drops them.
* Setting `properties.type = "mcp"` alone is **silently dropped** by ARM unless the request also carries `properties.mcpTools[]`. A subsequent GET returns `type: null`, and tool-creation calls then fail with `API type must be MCP`.
* `azurerm_api_management_api.id` ends with `;rev=N`. Composing `mcpTools[].operationId` from that ID produces a non-resolvable reference. The suffix must be stripped.

## The verified ARM shape

The MCP API is a separate APIM API of `type=mcp` whose `mcpTools[]` array references operations of an existing source API.

```json
PUT https://management.azure.com/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{apim}/apis/{mcp-api-name}?api-version=2025-09-01-preview
{
  "properties": {
    "displayName": "<friendly name shown in portal>",
    "description": "<optional>",
    "path": "<URL segment, e.g. flights-mcp>",
    "type": "mcp",
    "protocols": ["https"],
    "subscriptionRequired": true,
    "mcpTools": [
      {
        "name": "<tool name exposed to AI agents>",
        "description": "<tool description the model sees>",
        "operationId": "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{apim}/apis/{source-api}/operations/{operation}"
      }
    ]
  }
}
```

Key rules:

* `properties.type` must be the literal string `"mcp"`.
* `properties.mcpTools` is an inline array on the API. Do not use `mcpProperties.tools` and do not try to create child `/tools/{id}` resources.
* `properties.mcpTools[].operationId` must be the **full ARM resource ID** of the source operation. The short form `/apis/<api>/operations/<op>` is rejected. The ID must **not** include any `;rev=N` revision suffix.
* The MCP endpoint URL is then `https://{apim}.azure-api.net/{path}/mcp`. The `/mcp` suffix is added by APIM.
* The tool input schema is auto-generated from the source operation's OpenAPI parameters.
* All policies on the source API and source operation (rate limits, header injection, Key Vault-backed named values, etc.) automatically apply when the MCP tool is invoked.

## Option 1: az CLI (one-shot script)

Useful for ad-hoc creation, debugging, or when you intentionally want imperative control.

```pwsh
$sub  = "<subscription-id>"
$rg   = "<resource-group>"
$apim = "<apim-name>"
$src  = "<source-api-name>"          # e.g. aviationstack
$op   = "<operation-id>"             # e.g. listFlights
$mcp  = "<new-mcp-api-name>"         # e.g. aviationstack-mcp
$api  = "2025-09-01-preview"

$opId = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apim/apis/$src/operations/$op"

$body = @{
  properties = @{
    displayName          = "Aviationstack MCP"
    description          = "MCP server exposing $op."
    path                 = $mcp
    type                 = "mcp"
    protocols            = @("https")
    subscriptionRequired = $true
    mcpTools             = @(
      @{
        name        = "realTimeFlightData"
        description = "Returns real-time flight status."
        operationId = $opId
      }
    )
  }
} | ConvertTo-Json -Depth 10

$body | Out-File -Encoding utf8 mcp-body.json
az rest --method put `
  --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apim/apis/$mcp`?api-version=$api" `
  --body "@mcp-body.json"
Remove-Item mcp-body.json
```

To verify:

```pwsh
az rest --method get `
  --uri "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apim/apis/$mcp`?api-version=$api" `
  --query "properties.{type:type, tools:mcpTools, subReq:subscriptionRequired}"
```

A successful response shows `"type": "mcp"` and the populated `mcpTools` array.

## Option 2: Terraform with azapi (recommended)

The `azurerm` provider does not yet model `type=mcp` or `mcpTools`. Use `azapi_resource` with `2025-09-01-preview`. This is what the `apim-deployment/` solution in this repo uses; see [modules/mcp/main.tf](../apim-deployment/terraform/modules/mcp/main.tf).

```hcl
resource "azapi_resource" "mcp_api" {
  type      = "Microsoft.ApiManagement/service/apis@2025-09-01-preview"
  name      = "aviationstack-mcp"
  parent_id = var.apim_id

  body = {
    properties = {
      displayName          = "Aviationstack MCP"
      description          = "MCP server exposing the listFlights tool."
      path                 = "aviationstack-mcp"
      type                 = "mcp"
      protocols            = ["https"]
      subscriptionRequired = true
      mcpTools = [
        {
          name        = "realTimeFlightData"
          description = "Returns real-time flight status."
          # Strip the ;rev=N suffix that azurerm appends to api IDs.
          operationId = "${replace(var.source_api_id, "/;rev=\\d+/", "")}/operations/listFlights"
        }
      ]
    }
  }

  # The preview ARM API is not fully covered by azapi's local schema.
  schema_validation_enabled = false

  response_export_values = ["properties.type", "properties.mcpTools"]
}
```

Notes:

* `parent_id` is the APIM service resource ID, for example `module.apim.id`.
* `var.source_api_id` is the resource ID of the source REST API, for example `module.apis.api_ids["aviationstack"]`.
* If an MCP API already exists (created via portal or CLI), import it first:

```pwsh
terraform import 'azapi_resource.mcp_api' '/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.ApiManagement/service/{apim}/apis/{mcp-api-name}'
```

## Option 3: Bicep

Bicep accepts the same body. The schema does not yet describe `type=mcp` or `mcpTools`, so use untyped properties.

```bicep
param apimName string
param mcpApiName string = 'aviationstack-mcp'
param sourceApiName string = 'aviationstack'
param sourceOperationId string = 'listFlights'

resource service 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource sourceApi 'Microsoft.ApiManagement/service/apis@2024-05-01' existing = {
  parent: service
  name: sourceApiName
}

resource mcpApi 'Microsoft.ApiManagement/service/apis@2025-09-01-preview' = {
  parent: service
  name: mcpApiName
  properties: {
    displayName: 'Aviationstack MCP'
    description: 'MCP server exposing ${sourceOperationId}.'
    path: mcpApiName
    protocols: [ 'https' ]
    subscriptionRequired: true
    // type and mcpTools are not in the Bicep type yet; pass through untyped.
    type: 'mcp'
    mcpTools: [
      {
        name: 'realTimeFlightData'
        description: 'Returns real-time flight status.'
        // Bicep resource IDs do not carry the ;rev=N suffix, so no stripping needed here.
        operationId: '${sourceApi.id}/operations/${sourceOperationId}'
      }
    ]
  }
}
```

When `bicep build` complains about unknown properties, add `#disable-next-line BCP037` above the offending lines.

## Wiring into VS Code Copilot

Once the MCP API exists, register it as an MCP server in `.vscode/mcp.json`:

```json
{
  "inputs": [
    {
      "id": "apim-subscription-key",
      "type": "promptString",
      "description": "APIM subscription key for the MCP endpoint",
      "password": true
    }
  ],
  "servers": {
    "apim-mcp": {
      "type": "http",
      "url": "https://<apim>.azure-api.net/<mcp-api-path>/mcp",
      "headers": {
        "Ocp-Apim-Subscription-Key": "${input:apim-subscription-key}"
      }
    }
  }
}
```

Open the command palette, run `MCP: List Servers`, start the server, then ask Copilot in agent mode to use the tool by name (for example `realTimeFlightData`).

## Smoke test without VS Code

A direct JSON-RPC initialize call confirms the server is alive:

```pwsh
$key = "<apim-subscription-key>"
$body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1.0"}}}'
Invoke-WebRequest -UseBasicParsing -Method Post `
  -Uri "https://<apim>.azure-api.net/<mcp-api-path>/mcp" `
  -Headers @{ "Content-Type" = "application/json"; "Accept" = "application/json, text/event-stream"; "Ocp-Apim-Subscription-Key" = $key } `
  -Body $body
```

A 200 response with `serverInfo.name = "Azure API Management"` confirms end-to-end success. Replace `initialize` with `tools/list` to enumerate tools.

## Troubleshooting cheatsheet

| Symptom                                                  | Cause                                              | Fix                                                                                         |
| -------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| PUT succeeds, GET returns `type: null`                   | `mcpTools` missing from payload                    | Always include both `type: "mcp"` and a non-empty `mcpTools[]`                              |
| Tool call returns `API type must be MCP`                 | Same as above; `type` was dropped                  | Same as above                                                                               |
| `Either BackendId or MCP tools must be set, but not both`| `backendId` set alongside `mcpTools`               | Remove `backendId`; MCP APIs derive backend from the source operation                       |
| Tool returns 404 on invocation                           | `operationId` includes `;rev=N` or is the short form | Use the full ARM resource ID, stripped of any revision suffix                              |
| `tools/list` returns empty array                         | `mcpTools[].operationId` references a non-existent operation | Verify the source API name, operation id, and full ARM path                            |
| Anonymous calls return 401 unexpectedly                  | `subscriptionRequired: true`                       | Either send `Ocp-Apim-Subscription-Key` or set `subscriptionRequired: false`                |
| Azure Bicep build error `BCP037` on `type` or `mcpTools` | Bicep types don't cover preview fields yet         | Add `#disable-next-line BCP037` above the offending property                                |

## References

* Working Terraform implementation: [apim-deployment/terraform/modules/mcp](../apim-deployment/terraform/modules/mcp)
* Today's iteration history: [docs/activity-log-2026-05-26.md](activity-log-2026-05-26.md)
