data "azurerm_ssh_public_key" "ssh_key" {
  name                = var.azure_ssh_key_name
  resource_group_name = var.azure_ssh_key_resource_group
}
