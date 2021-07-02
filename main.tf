terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "2.57.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {

    common = {
        location    = "eastus"
        name        = "jenkins-demo"
    }
    
    vm = {
        jenkins = { 
            cloud-init  = <<EOT
            #cloud-config
            package_upgrade: true
            runcmd:
            - apt install openjdk-8-jdk -y
            - wget -qO - https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo apt-key add -
            - sh -c 'echo deb https://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
            - apt-get update && apt-get install jenkins -y
            - service jenkins restart
            EOT
            admin_name     = "azureuser"
            admin_password = "CHANGE_ME"
        }
    }

    pubilc_ip = {
        jenkins = { name = "jenkins" }
    }
}

resource "azurerm_resource_group" "rg" {
    name        = format("%s-rg", local.common.name)
    location    = local.common.location
}

resource "azurerm_virtual_network" "vnet" {
    name                = format("%s-vnet", local.common.name)
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location
    address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
    name                 = "default"
    virtual_network_name = azurerm_virtual_network.vnet.name
    resource_group_name  = azurerm_resource_group.rg.name
    address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_linux_virtual_machine" "vm" {
    for_each                = local.vm
    name                    = format("%s-vm", each.key)
    resource_group_name     = azurerm_resource_group.rg.name
    location                = azurerm_resource_group.rg.location
    size                    = "Standard_B1s"
    admin_username          = each.value.admin_name
    network_interface_ids   = [ contains(keys(azurerm_network_interface.nic), each.key) ? azurerm_network_interface.nic[each.key].id : null ]

    admin_password          = each.value.admin_password
    disable_password_authentication = false

    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    custom_data = contains(keys(each.value), "cloud-init") ? base64encode(each.value.cloud-init) : null
}

resource "azurerm_network_interface" "nic" {
    for_each            = local.vm
    name                = format("%s-nic", each.key)
    location            = azurerm_resource_group.rg.location 
    resource_group_name = azurerm_resource_group.rg.name

    ip_configuration {
        name                            = "internal"
        subnet_id                       = azurerm_subnet.subnet.id
        private_ip_address_allocation   = "Dynamic"
        public_ip_address_id            = contains(keys(azurerm_public_ip.pip), each.key) ? azurerm_public_ip.pip[each.key].id : null
    }
}

resource "azurerm_public_ip" "pip" {
    for_each            = local.pubilc_ip
    name                = format("%s-pip", each.key)
    resource_group_name = azurerm_resource_group.rg.name
    location            = azurerm_resource_group.rg.location
    allocation_method   = "Dynamic"
}

resource "azurerm_network_security_group" "nsg" {
    for_each            = local.vm
    name                = format("%s-nsg", each.key)
    location            = azurerm_resource_group.rg.location 
    resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_network_interface_security_group_association" "nsg_association" {
    for_each                    = local.vm
    network_interface_id        = azurerm_network_interface.nic[each.key].id
    network_security_group_id   = azurerm_network_security_group.nsg[each.key].id
}

resource "azurerm_network_security_rule" "nsg_rule_8080" {
    for_each                    = local.vm
    name                        = format("%s_8080", each.key)
    priority                    = 100
    direction                   = "Inbound"
    access                      = "Allow"
    protocol                    = "Tcp"
    source_port_range           = "*"
    destination_port_range      = "8080"
    source_address_prefix       = "*"
    destination_address_prefix  = "*"
    resource_group_name         = azurerm_resource_group.rg.name
    network_security_group_name = format("%s-nsg", each.key)
}

resource "azurerm_network_security_rule" "nsg_rule_http" {
    for_each                    = local.vm
    name                        = format("%s_http", each.key)
    priority                    = 150
    direction                   = "Inbound"
    access                      = "Allow"
    protocol                    = "Tcp"
    source_port_range           = "*"
    destination_port_range      = "80"
    source_address_prefix       = "*"
    destination_address_prefix  = "*"
    resource_group_name         = azurerm_resource_group.rg.name
    network_security_group_name = format("%s-nsg", each.key)
}

resource "azurerm_network_security_rule" "nsg_rule_ssh" {
    for_each                    = local.vm
    name                        = format("%s_ssh", each.key)
    priority                    = 200
    direction                   = "Inbound"
    access                      = "Allow"
    protocol                    = "Tcp"
    source_port_range           = "*"
    destination_port_range      = "22"
    source_address_prefix       = "*"
    destination_address_prefix  = "*"
    resource_group_name         = azurerm_resource_group.rg.name
    network_security_group_name = format("%s-nsg", each.key)
}