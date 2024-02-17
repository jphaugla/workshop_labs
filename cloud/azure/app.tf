locals {
  zones = ["1", "2", "3"]
  admin_username = "adminuser"
}

resource "azurerm_public_ip" "app-ip" {
    count                        = var.include_app == "yes" ? 1 : 0
    name                         = "${var.owner}-${var.resource_name}-public-ip-app"
    location                     = var.virtual_network_location
    resource_group_name          = local.resource_group_name
    allocation_method            = "Dynamic"
    sku                          = "Basic"
    tags                         = local.tags
}

resource "azurerm_network_interface" "app" {
    count                       = var.include_app == "yes" ? 1 : 0
    name                        = "${var.owner}-${var.resource_name}-ni-app"
    location                    = var.virtual_network_location
    resource_group_name         = local.resource_group_name
    tags                        = local.tags

    ip_configuration {
    name                          = "network-interface-app-ip"
    subnet_id                     = azurerm_subnet.sn[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.app-ip[0].id
    }
}

resource "azurerm_linux_virtual_machine" "app" {
    count                 = var.include_app == "yes" && var.create_ec2_instances == "yes" ? 1 : 0
    name                  = "${var.owner}-${var.resource_name}-vm-app"
    location              = var.virtual_network_location
    resource_group_name   = local.resource_group_name
    size                  = var.app_vm_size
    tags                  = local.tags

    network_interface_ids = [azurerm_network_interface.app[0].id]

    admin_username                  = local.admin_username     # is this still required with an admin_ssh key block?
    disable_password_authentication = true
    admin_ssh_key {
        username                      = local.admin_username    # a bug in the provider requires this to be adminuser
        public_key                    = data.azurerm_ssh_public_key.ssh_key.public_key
    }

    source_image_reference {
       publisher = "Canonical"
       offer     = "0001-com-ubuntu-server-jammy"
       sku       = "22_04-lts-gen2"
       version   = "latest"
    }

    # os_disk {
    #     name      = "${var.owner}-${var.resource_name}-osdisk-app"
    #     caching   = "ReadWrite" # possible values: None, ReadOnly and ReadWrite
    #     storage_account_type = "Standard_LRS" # possible values: Standard_LRS, StandardSSD_LRS, Premium_LRS, Premium_SSD, StandardSSD_ZRS and Premium_ZRS
    # }
    os_disk {
        name      = "${var.owner}-${var.resource_name}-app-osdisk"
        caching   = "ReadWrite" # possible values: None, ReadOnly and ReadWrite
        storage_account_type = "Standard_LRS" # possible values: Standard_LRS, StandardSSD_LRS, Premium_LRS, Premium_SSD, StandardSSD_ZRS and Premium_ZRS
        disk_size_gb = var.app_disk_size
    }
    

    user_data = base64encode(<<EOF
#!/bin/bash -xe
echo "Shutting down and disabling firewalld -- SECURITY RISK!!"
systemctl stop firewalld
systemctl disable firewalld
apt update && sudo apt upgrade -y 
apt install -y podman
pip3 install podman-compose
apt install -y git
cd /home/adminuser
git clone https://github.com/jphaugla/workshop_labs.git
git clone https://github.com/nollenr/crdb-multi-region-demo.git
chown -R adminuser:adminuser crdb-multi-region-demo
chown -R adminuser:adminuser workshop_labs
    EOF
    )
}
