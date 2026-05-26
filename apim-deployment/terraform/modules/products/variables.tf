variable "apim_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "products" {
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
  type = map(object({
    display_name = string
    product_key  = string
    state        = optional(string, "active")
  }))
  default = {}
}
