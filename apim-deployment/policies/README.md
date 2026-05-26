# Policies

Raw policy XML files referenced from Terraform via `file()`.

| File | Scope | Referenced from |
| ---- | ----- | --------------- |
| `global.xml` | Global (service) | `var.global_policy_xml_path` in root `variables.tf` |
| (add yours)  | API / operation / product | `var.apis`, `var.products` in `terraform.tfvars` |

Naming convention: `<scope>-<name>.xml` (e.g. `api-aircrafts.xml`, `op-aircrafts-getBookings.xml`, `product-starter.xml`).
