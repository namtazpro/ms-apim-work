provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
}

# Remote state backend (commented out — using local state for dev).
# To promote to remote state, fill in the values, run:
#   terraform init -migrate-state
#
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "rg-tfstate"
#     storage_account_name = "sttfstateapimv2"
#     container_name       = "tfstate"
#     key                  = "apim-deployment/dev.tfstate"
#   }
# }
