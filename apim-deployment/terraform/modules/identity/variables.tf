variable "apim_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "identity_providers" {
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
  type = map(object({
    display_name = string
    description  = optional(string, "")
    type         = optional(string, "custom")
  }))
  default = {}
}
