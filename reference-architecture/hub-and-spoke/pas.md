# Pivotal Application Service on Spoke Network

In this lab you will deploy Pivotal Application Service on an existing spoke VNet.

## Pre-requisites

Before doing this lab ensure you have the following.

* [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
* [Terraform CLI](https://www.terraform.io/intro/getting-started/install.html)
* Git CLI (`brew install git` on Mac)
* An Environment file describing your test environment for the lab, ask your instructor
* Optional: `jq` (`brew install jq`)



## Deploy the Solution

1. Use the `clientId`, `clientSecret` and `tenant` from your environment file to log into the Azure CLI as your Service Principal
```
az login --service-principal --username <clientId> --password <clientSecret> --tenant <tenant>
```
1. Delegate `Owner` permissions over the two resource groups to your AAD account. This will enable you to see the resource groups in your Azure Portal. (Substitute `<subscription>`, `<network_rg>` and `<pas_rg>` with the corresponding values from your environment file)
```
az role assignment create --assignee "<your_aad_email>" --role Owner --scope /subscription/<subscription>/resourcegroups/<network_rg>
az role assignment create --assignee "<your_aad_email>" --role Owner --scope /subscription/<subscription>/resourcegroups/<pas_rg>
```
1. (Optional) Log back into your personal account via the CLI (You now have just as much permission over these resources as your Service Principal)
```
az login
az account set --subscription <subscription>
```
1. Clone the `terraforming-azure` repo and navigate to the `terraforming-pas` directory. I reference my fork in the command below as plugable VNets are not yet supported in `pivotal-cf/terraforming-azure`.
```
git clone git@github.com:jseely/terraforming-azure.git
cd terraforming-azure/terraforming-pas
```
1. Create a `terraform.tfvars` file with the following content. Replace all `<variable>` references with values from the environment file. 
```
subscription_id = "<subscription>"
tenant_id = "<tenant>"
client_id = "<clientId>"
client_secret = "<clientSecret>"

env_name = "<envName>"
env_short_name = "<storageAccountPrefix>"
location = "<location>"
ops_manager_image_uri = "YOUR-OPSMAN-IAMGE-URI"
dns_suffix = "<dnsSuffix>"
vm_admin_username = "YOUR-ADMIN-USERNAME"

pcf_vnet_rg = "<network_rg>"
```
1. Replace `YOUR-OPSMAN-IMAGE-URI` with the URL for the Ops Manager Azure image you want to boot. You can find this in the PDF included with the Ops Manager release on [Pivotal Network](https://network.pivotal.io/).
1. Replace `YOUR-ADMIN-USERNAME` with a username of your choice
1. Initialize the directory based on the `terraform.tfvars` file you have created
```
terraform init
```
1. Apply the terraform template
```
terraform apply
```

## Pre-requisite: Set up student environment 

1. Set the `ENV_NAME`, `LOCATION` and `DNS_SUFFIX` variables and run the `create-pas-infra.sh` script.
1. Give `${ENV_NAME}.env.json` file to students

## Cleanup: Tear down student environment

1. Set the `ENV_FILE` variable to the `${ENV_NAME}.env.json` file and run the `cleanup-pas-infra.sh` script 

