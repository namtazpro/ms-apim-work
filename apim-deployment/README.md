# apim-deployment

Terraform solution to deploy and manage an Azure API Management (APIM) instance and its content.

## Scope

Managed by this Terraform code:

- APIM instance (SKU `StandardV2_1`)
- APIs and operations (with per-API / per-operation policies)
- Global, product, and API policies
- Products and subscriptions
- Named values and backends
- Identity providers, users, and groups

Out of scope for now (can be added later): networking (VNet integration), private endpoints, custom domains, certificates, regional gateways, CI/CD environments other than dev.

## Target Azure environment (dev)

| Setting          | Value                                  |
| ---------------- | -------------------------------------- |
| Subscription ID  | `8bcaf808-26b1-45e4-8340-ec627a7afa0a` |
| Resource group   | `rg-apimv2`                            |
| Region           | `westeurope`                           |
| APIM name        | `apimv2may2026`                        |
| APIM SKU         | `StandardV2_1` (1 unit)                |
| Zones            | `["1"]` (single-zone)                  |
| Publisher        | Vincent Rouet (`vincent.rouet@microsoft.com`) |

## Repository layout

```text
apim-deployment/
  terraform/
    providers.tf          # azurerm + azapi providers, backend
    versions.tf           # required versions
    variables.tf          # root inputs
    locals.tf             # naming + computed values
    main.tf               # root composition (calls modules)
    outputs.tf
    terraform.tfvars.example
    modules/
      apim/                 # APIM service (with system-assigned MI)
      apis/                 # APIs + operations + policies
      products/             # products, product-API links, subscriptions
      named-values-backends/
      identity/             # identity providers, users, groups
  policies/                 # raw policy XML files (loaded via file())
  apis/                     # OpenAPI specs (loaded via file())
```

The GitHub Actions workflow lives at the **repo root** under
[.github/workflows/apim-deploy.yml](../.github/workflows/apim-deploy.yml)
(GitHub Actions only discovers workflows at the repo root).

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) signed in (`az login`) with **Contributor** on the target subscription
- (Optional) [tflint](https://github.com/terraform-linters/tflint) for local linting

## Local deploy

```pwsh
cd apim-deployment/terraform

# one-time
Copy-Item terraform.tfvars.example terraform.tfvars

az account set --subscription 8bcaf808-26b1-45e4-8340-ec627a7afa0a

terraform init
terraform plan  -out tfplan
terraform apply tfplan
```

To destroy the dev environment:

```pwsh
terraform destroy
```

> APIM `StandardV2` provisioning typically takes **30-45 minutes** for the first deploy. Subsequent updates to APIs / policies are fast.

## Iterating

This solution is **data-driven**. To add content, edit `terraform.tfvars` (or create one tfvars per concern) and add the matching policy / OpenAPI file:

| What you want to add        | Where                                                                  |
| --------------------------- | ---------------------------------------------------------------------- |
| A new API                   | Drop OpenAPI in `apis/`, add an entry to `apis` map in `terraform.tfvars`. |
| A per-operation policy      | Drop XML in `policies/`, reference it from the `apis` map entry.        |
| A new product               | Add an entry to `products` map, list the API names to attach.           |
| A backend                   | Add an entry to `backends` map.                                         |
| A named value               | Add an entry to `named_values` map.                                     |
| An identity provider / user | Add an entry to the corresponding map in the `identity` variable.       |

Then:

```pwsh
terraform plan
terraform apply
```

## CI/CD

A GitHub Actions workflow at the repo root deploys on push to `main` when files under `apim-deployment/**` change. It uses OIDC federation (no client secrets stored). See the workflow file for the required GitHub secrets / variables:

- `AZURE_CLIENT_ID` (federated app registration)
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

## State

Local state for now (dev only). To promote to remote state, uncomment the `azurerm` backend block in [terraform/providers.tf](terraform/providers.tf) and run `terraform init -migrate-state`.
