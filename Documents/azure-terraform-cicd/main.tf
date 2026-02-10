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

# ---------------- Random suffix ----------------
resource "random_integer" "rand" {
  min = 10000
  max = 99999
}

# ---------------- Variables ----------------
variable "location" {
  type    = string
  default = "Canada East"
}

variable "vm_size" {
  type    = string
  default = "Standard_B1s"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "admin_ssh_public_key" {
  type        = string
  description = "SSH public key"
}

# ---------------- Local Names ----------------
locals {
  suffix   = random_integer.rand.result
  rg_name  = "rg-terraform-cicd-${local.suffix}"
  vnet     = "vnet-terraform-${local.suffix}"
  subnet   = "subnet-01"
  pip_name = "pip-${local.suffix}"
  nic_name = "nic-${local.suffix}"
  vm_name  = "vm-${local.suffix}"
  aci_name = "docker-${local.suffix}"
  dns_lbl  = "tfc${local.suffix}"
}

# ---------------- Resource Group ----------------
resource "azurerm_resource_group" "rg" {
  name     = local.rg_name
  location = var.location
}

# ---------------- Virtual Network ----------------
resource "azurerm_virtual_network" "vnet" {
  name                = local.vnet
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = local.subnet
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ---------------- Public IP ----------------
resource "azurerm_public_ip" "pip" {
  name                = local.pip_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ---------------- Network Interface ----------------
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

# ---------------- Linux Virtual Machine ----------------
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

# ---------------- Azure Container Instance ----------------
resource "azurerm_container_group" "container" {
  name                = local.aci_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Public"
  dns_name_label      = local.dns_lbl
  os_type             = "Linux"

  container {
    name   = "nginx"
    image  = "nginx:latest"
    cpu    = 0.5
    memory = 1.5

    ports {
      port     = 80
      protocol = "TCP"
    }
  }
}

# ---------------- Outputs ----------------
output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "vm_public_ip" {
  value = azurerm_public_ip.pip.ip_address
}

output "container_fqdn" {
  value = azurerm_container_group.container.fqdn
}
