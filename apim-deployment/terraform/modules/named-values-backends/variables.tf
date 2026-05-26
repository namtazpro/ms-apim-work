variable "apim_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "named_values" {
  type = map(object({
    display_name        = string
    value               = optional(string, null)
    secret              = optional(bool, false)
    key_vault_secret_id = optional(string, null)
    tags                = optional(list(string), [])
  }))
  default = {}
}

variable "backends" {
  type = map(object({
    url      = string
    protocol = optional(string, "http")
  }))
  default = {}
}
