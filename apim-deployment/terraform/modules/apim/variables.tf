variable "name" {
  type        = string
  description = "APIM instance name (globally unique)."
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "sku_name" {
  type        = string
  description = "APIM SKU, format tier_capacity (e.g. StandardV2_1)."
}

variable "zones" {
  type        = list(string)
  description = "Availability zones. Empty list disables zones."
  default     = []
}

variable "publisher_name" {
  type = string
}

variable "publisher_email" {
  type = string
}

variable "global_policy_xml_path" {
  type        = string
  description = "Path to global policy XML. Empty string or missing file = skip."
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
