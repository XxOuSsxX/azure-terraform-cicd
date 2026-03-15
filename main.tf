provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-terraform-cicd"
  location = "Canada Central"
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-terraform-cicd"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s"

  admin_username = "azureuser"

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.admin_ssh_public_key
  }
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the VM"
  type        = string
}