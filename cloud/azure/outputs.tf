output "virtual_network_name" {
  description = "Virtual Network Name"
  value = azurerm_virtual_network.vm01.name
}

output "virtual_network_id" {
  description = "virtual Network ID"
  value = azurerm_virtual_network.vm01.id
}

output "public_ip_address" {
   description = "public ip address of the node"
   value = azurerm_linux_virtual_machine.app.0.public_ip_address
}
