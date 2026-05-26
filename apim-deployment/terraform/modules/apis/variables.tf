variable "apim_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "apis" {
  description = "Map of APIs (see root variables.tf for the schema)."
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
