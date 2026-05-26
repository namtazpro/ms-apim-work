---
title: Activity Log - 2026-05-26
description: Chronological summary of work done on the apim-deployment Terraform solution today
author: Vincent Rouet
ms.date: 2026-05-26
ms.topic: reference
keywords:
  - apim
  - terraform
  - mcp
  - activity-log
---

## Activity Log - 2026-05-26

High-level chronological summary of work on `apim-deployment/` today.

## Starting state

* APIM instance `apimv2may2026` (StandardV2_1) already deployed by Terraform.
* `aviationstack` REST API already imported with OpenAPI spec.
* Subscription key already in Key Vault `kv-apimv2-may2026`, consumed by APIM via managed identity.
* `<rate-limit-by-key>` (5 calls/min) on the `listFlights` operation.

## Today's milestones

### 1. Goal: expose the Aviationstack REST API as an MCP server

Triggered by: *"can you enable this flight API to be exposed as an MCP in APIM"*.

### 2. ARM discovery (research)

* Attempted direct `az rest` PUT with several payload shapes inferred from TypeSpec sources.
* All attempts had `type=mcp` silently dropped by the ARM endpoint.
* Concluded: the public ARM contract requires fields not documented in the TypeSpec, so switched to portal-first.

### 3. Portal-first creation

* Created MCP API `aviationstack-mcp` via the Azure portal.
* Added one tool `realTimeFlightData` mapped to `aviationstack/listFlights`.
* Captured the resulting ARM JSON with `az rest GET`.

### 4. ARM shape decoded

Key findings from the portal-created resource:

* `properties.type = "mcp"` (discriminator).
* `properties.mcpTools[]` is an inline array on the API — NOT `mcpProperties.tools`, NOT child `/tools/{id}` resources (TypeSpec was misleading).
* `operationId` must be the full ARM resource ID of the source operation.
* Tool input schema is auto-generated from the source operation's OpenAPI parameters.

### 5. Reproduced via direct ARM PUT

* Idempotent PUT with the discovered minimal body succeeded.
* Confirmed `type=mcp` persists when accompanied by `mcpTools[]`.

### 6. Wired into VS Code Copilot

* Created `.vscode/mcp.json` with HTTP server config.
* Used `${input:apim-subscription-key}` prompt so no secret is committed.

### 7. Terraform port (modules/mcp)

* New module `apim-deployment/terraform/modules/mcp/` using `azapi_resource` and ARM API `2025-09-01-preview`.
* Added `mcp_servers` root variable and `mcp_endpoints` root output.
* Strips the `;rev=N` suffix from `azurerm_api_management_api.id` before composing `operationId`.
* Imported the portal-created API into Terraform state.
* `terraform plan` confirmed zero behavioural drift.
* `terraform apply` brought the resource fully under Terraform management.

### 8. Hardened security

* Flipped `subscription_required = true` (portal default was `false`).
* Verified: anonymous calls return 401; calls with the master subscription key return 200.
* Applied via Terraform.

### 9. End-to-end smoke test from Copilot

* Copilot agent auto-discovered the MCP server and invoked `realTimeFlightData`.
* Returned 745 Air France flights from CDG today (87 scheduled, 11 active, 2 landed).
* Confirmed the inherited rate-limit policy and Key Vault-backed `access_key` injection are both still in effect.

## Final state

* Entire stack deploys from a clean subscription with `terraform init && terraform apply`.
* MCP endpoint: `https://apimv2may2026.azure-api.net/aviationstack-mcp/mcp`.
* Adding more MCP tools is a one-line edit in `terraform.tfvars` under `mcp_servers.aviationstack-mcp.tools`.
* Repository memory `/memories/repo/apim-deployment.md` updated with the MCP discovery pattern and gotchas.

## Files touched today

* [apim-deployment/terraform/modules/mcp/main.tf](../apim-deployment/terraform/modules/mcp/main.tf) (new)
* [apim-deployment/terraform/modules/mcp/variables.tf](../apim-deployment/terraform/modules/mcp/variables.tf) (new)
* [apim-deployment/terraform/modules/mcp/outputs.tf](../apim-deployment/terraform/modules/mcp/outputs.tf) (new)
* [apim-deployment/terraform/main.tf](../apim-deployment/terraform/main.tf) (added `mcp` module call)
* [apim-deployment/terraform/variables.tf](../apim-deployment/terraform/variables.tf) (added `mcp_servers`)
* [apim-deployment/terraform/outputs.tf](../apim-deployment/terraform/outputs.tf) (added `mcp_endpoints`)
* [apim-deployment/terraform/terraform.tfvars](../apim-deployment/terraform/terraform.tfvars) (added `mcp_servers` block)
* [.vscode/mcp.json](../.vscode/mcp.json) (new)
