variable "subscription_id" {
  description = "Azure subscription ID where APIM is deployed."
  type        = string
  default     = "8bcaf808-26b1-45e4-8340-ec627a7afa0a"
}

variable "resource_group_name" {
  description = "Resource group that will host the APIM instance."
  type        = string
  default     = "rg-apimv2"
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "environment" {
  description = "Environment short name (used in tags / naming)."
  type        = string
  default     = "dev"
}

variable "apim_name" {
  description = "Name of the APIM instance. Must be globally unique."
  type        = string
  default     = "apimv2may2026"
}

variable "apim_sku" {
  description = "APIM SKU. Format: <tier>_<capacity>. The capacity suffix is the unit count (e.g. StandardV2_1 = 1 unit)."
  type        = string
  default     = "StandardV2_1"
}

variable "apim_zones" {
  description = <<-EOT
    Availability zones for the APIM instance.
    NOTE: The azurerm provider currently only accepts `zones` on the `Premium` SKU.
    For StandardV2, leave this as [] (zone pinning via azurerm is not supported yet;
    to pin a zone on StandardV2 you must switch the apim module to the azapi provider).
  EOT
  type    = list(string)
  default = []
}

variable "publisher_name" {
  description = "APIM publisher display name."
  type        = string
  default     = "Vincent Rouet"
}

variable "publisher_email" {
  description = "APIM publisher email."
  type        = string
  default     = "vincent.rouet@microsoft.com"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    workload = "apim-demo"
    owner    = "virouet"
  }
}

# ---------------------------------------------------------------------------
# Content variables (all default to empty so the user adds incrementally).
# ---------------------------------------------------------------------------

variable "global_policy_xml_path" {
  description = "Path (relative to repo root or absolute) to the global APIM policy XML. Empty string = no global policy override."
  type        = string
  default     = "../policies/global.xml"
}

variable "apis" {
  description = <<-EOT
    Map of APIs to provision. Example:

    {
      "aircrafts" = {
        display_name  = "Aircrafts API"
        path          = "aircrafts"
        protocols     = ["https"]
        openapi_path  = "../apis/aircrafts.openapi.json"
        api_policy_xml_path = "../policies/aircrafts.xml" # optional, "" to skip
        operation_policies = {
          # operation_id = "../policies/aircrafts-getBookings.xml"
        }
      }
    }
  EOT
  type = map(object({
    display_name        = string
    path                = string
    protocols           = list(string)
    openapi_path        = string
    api_policy_xml_path = optional(string, "")
    operation_policies  = optional(map(string), {})
  }))
  default = {}
}

variable "products" {
  description = <<-EOT
    Map of products. Example:

    {
      "starter" = {
        display_name           = "Starter"
        description            = "Starter product"
        subscription_required  = true
        approval_required      = false
        published              = true
        api_names              = ["aircrafts"]
        policy_xml_path        = "../policies/product-starter.xml" # optional, "" to skip
      }
    }
  EOT
  type = map(object({
    display_name          = string
    description           = optional(string, "")
    subscription_required = optional(bool, true)
    approval_required     = optional(bool, false)
    published             = optional(bool, true)
    api_names             = optional(list(string), [])
    policy_xml_path       = optional(string, "")
  }))
  default = {}
}

variable "subscriptions" {
  description = <<-EOT
    Map of subscriptions. Example:

    {
      "starter-sub-1" = {
        display_name = "Starter Subscription 1"
        product_key  = "starter" # key in var.products
        state        = "active"
      }
    }
  EOT
  type = map(object({
    display_name = string
    product_key  = string
    state        = optional(string, "active")
  }))
  default = {}
}

variable "named_values" {
  description = <<-EOT
    Map of named values.

    Provide EITHER `value` (inline) OR `key_vault_secret_id` (Key Vault reference).
    When `key_vault_secret_id` is set, `value` is ignored and APIM pulls the secret
    via its system-assigned managed identity (requires `Key Vault Secrets User`
    role on the vault).

    Examples:

    {
      "backend-url" = {
        display_name = "backend-url"
        value        = "https://backend.example.com"
        secret       = false
      }
      "my-api-key" = {
        display_name        = "my-api-key"
        secret              = true
        key_vault_secret_id = "https://my-kv.vault.azure.net/secrets/my-api-key"
      }
    }
  EOT
  type = map(object({
    display_name        = string
    value               = optional(string, null)
    secret              = optional(bool, false)
    key_vault_secret_id = optional(string, null)
    tags                = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.named_values :
      (v.value != null) != (v.key_vault_secret_id != null)
    ])
    error_message = "Each named_value must set exactly one of `value` or `key_vault_secret_id`."
  }
}

variable "backends" {
  description = <<-EOT
    Map of backends. Example:

    {
      "aircrafts-backend" = {
        url      = "https://backend.example.com/aircrafts"
        protocol = "http"
      }
    }
  EOT
  type = map(object({
    url      = string
    protocol = optional(string, "http")
  }))
  default = {}
}

variable "identity_providers" {
  description = <<-EOT
    Map of identity providers. Example:

    {
      "aad" = {
        type          = "aad"
        client_id     = "..."
        client_secret = "..." # consider Key Vault later
        allowed_tenants = ["<tenant-id>"]
      }
    }
  EOT
  type = map(object({
    type            = string
    client_id       = string
    client_secret   = string
    allowed_tenants = optional(list(string), [])
    signin_tenant   = optional(string, null)
  }))
  default = {}
}

variable "users" {
  description = <<-EOT
    Map of APIM users. Example:

    {
      "alice" = {
        first_name = "Alice"
        last_name  = "Doe"
        email      = "alice@example.com"
        state      = "active"
      }
    }
  EOT
  type = map(object({
    first_name = string
    last_name  = string
    email      = string
    state      = optional(string, "active")
    note       = optional(string, "")
  }))
  default = {}
}

variable "groups" {
  description = <<-EOT
    Map of APIM groups. Example:

    {
      "premium-customers" = {
        display_name = "Premium customers"
        description  = "Customers on the premium tier"
      }
    }
  EOT
  type = map(object({
    display_name = string
    description  = optional(string, "")
    type         = optional(string, "custom") # custom | external
  }))
  default = {}
}
