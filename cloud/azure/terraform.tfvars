# ----------------------------------------
# Globals
# ----------------------------------------
owner                      = "jphaugland"
resource_name              = "usbank" # This is NOT the resource group name, but is used to form the resource group name unless it is passed in as multi-region-resource-group-name
multi_region               = false

# ----------------------------------------
# My IP Address - security group config
# ----------------------------------------
my_ip_address              = "174.141.204.193"

# Azure Locations: "australiacentral,australiacentral2,australiaeast,australiasoutheast,brazilsouth,brazilsoutheast,brazilus,canadacentral,canadaeast,centralindia,centralus,centraluseuap,eastasia,eastus,eastus2,eastus2euap,francecentral,francesouth,germanynorth,germanywestcentral,israelcentral,italynorth,japaneast,japanwest,jioindiacentral,jioindiawest,koreacentral,koreasouth,malaysiasouth,northcentralus,northeurope,norwayeast,norwaywest,polandcentral,qatarcentral,southafricanorth,southafricawest,southcentralus,southeastasia,southindia,swedencentral,swedensouth,switzerlandnorth,switzerlandwest,uaecentral,uaenorth,uksouth,ukwest,westcentralus,westeurope,westindia,westus,westus2,westus3,austriaeast,chilecentral,eastusslv,israelnorthwest,malaysiawest,mexicocentral,newzealandnorth,southeastasiafoundational,spaincentral,taiwannorth,taiwannorthwest"
# ----------------------------------------
# Resource Group
# ----------------------------------------
resource_group_location    = "eastus2"

# ----------------------------------------
# Existing Key Info
# ----------------------------------------
azure_ssh_key_name           = "jhaugland-eastus2"
azure_ssh_key_resource_group = "jhaugland-rg"
ssh_private_key              = "~/.ssh/jhaugland-eastus2.pem"

# ----------------------------------------
# Network
# ----------------------------------------
virtual_network_cidr       = "192.168.3.0/24"
virtual_network_location   = "eastus2"

# ----------------------------------------
# APP Instance Specifications
# ----------------------------------------
include_app                = "yes"
app_vm_size                = "Standard_B4ms"
app_disk_size              = 64
app_resize_homelv          = "no"  # if the app_disk_size is greater than 64, then set this to "yes" so that the disk will be resized.  See warnings in vars.tf!

# ----------------------------------------
# CRDB Specifications
# ----------------------------------------
crdb_version               = "23.2.0"
