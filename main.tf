terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# -------- Random (évite les conflits de noms) --------
resource "random_integer" "rand" {
  min = 10000
  max = 99999
}

# -------- Variables --------
variable "location" {
  type    = string
  default = "Canada East"
}

variable "vm_size" {
  default = "SStandard_B1s"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "admin_ssh_public_key" {
  type        = string
  description = "SSH public key for VM access (ex: ssh-rsa AAAA... user@pc)"
}

# -------- Noms uniques --------
locals {
  rg_name   = "rg-terraform-cicd-${random_integer.rand.result}"
  vnet_name = "vnet-terraform-cicd-${random_integer.rand.result}"
  pip_name  = "pip-vm-terraform-${random_integer.rand.result}"
  nic_name  = "nic-vm-${random_integer.rand.result}"
  vm_name   = "vm-terraform-${random_integer.rand.result}"
  aci_name  = "docker-container-${random_integer.rand.result}"
  dns_label = "tfc${random_integer.rand.result}"
}

# -------- Resource Group --------
resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = var.location
}

# -------- VNet / Subnet --------
resource "azurerm_virtual_network" "vnet" {
  name                = local.vnet_name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-01"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# -------- Public IP (Standard) --------
resource "azurerm_public_ip" "pip" {
  name                = local.pip_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# -------- NIC --------
resource "azurerm_network_interface" "nic" {
  name                = local.nic_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# -------- VM Linux (SSH) --------
resource "azurerm_linux_virtual_machine" "vm" {
  name                = local.vm_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# -------- Container (ACI) --------

resource "azurerm_container_group" "container" {
  name                = "docker-container"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Public"
  dns_name_label      = "terraformdocker${random_integer.rand.result}"
  os_type             = "Linux"

  container {
    name   = "nginx"
    image  = "nginx:latest"
    cpu    = "0.5"
    memory = "1.5"

    ports {
      port     = 80
      protocol = "TCP"
    }
  }
}


# -------- Outputs --------
output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "vm_public_ip" {
  value = azurerm_public_ip.pip.ip_address
}

output "container_fqdn" {
  value = azurerm_container_group.container.fqdn
}