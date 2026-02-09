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

# -------- Variables (meilleur que hardcoder) --------
variable "location" {
  type    = string
  default = "Canada East"
}

variable "vm_size" {
  type    = string
  # Mets une taille plus probable que B2s. Change si Azure refuse.
  default = "Standard_DS1_v2"
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

variable "admin_ssh_public_key" {
  type        = string
  description = "SSH public key for VM access"
}

# -------- Resource Group --------
resource "azurerm_resource_group" "rg" {
  name     = "rg-terraform-cicd-test-01"
  location = var.location
}

# -------- VNet / Subnet --------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-terraform-cicd"
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

# -------- Public IP (utile pour tester la VM) --------
resource "azurerm_public_ip" "pip" {
  name                = "pip-vm-terraform"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

# -------- NIC --------
resource "azurerm_network_interface" "nic" {
  name                = "nic-vm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }

  depends_on = [azurerm_subnet.subnet]
}

# -------- VM Linux --------
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-terraform"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size

  admin_username = var.admin_username

variable "admin_ssh_public_key" {
  type        = string
  description = "SSH public key for the VM admin user"
}


admin_ssh_key {
  username   = var.admin_username
  public_key = var.admin_ssh_public_key
}

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  disable_password_authentication = true

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


# -------- Random pour DNS du container --------
resource "random_integer" "rand" {
  min = 10000
  max = 99999
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

# -------- Outputs (pratique pour ton devoir) --------
output "vm_public_ip" {
  value = azurerm_public_ip.pip.ip_address
}

output "container_fqdn" {
  value = azurerm_container_group.container.fqdn
}


