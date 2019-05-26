# Pivotal Application Service on Spoke Network

In this lab you will deploy Pivotal Application Service on Azure with VNet resources deployed to one resource group and all other components deployed to another.

## Deploy the Solution

### Pre-requisites

Before doing this lab ensure you have the following.

* [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
* [Terraform CLI](https://www.terraform.io/intro/getting-started/install.html)
* Git CLI (`brew install git` on Mac)
* An Environment file describing your test environment for the lab, ask your instructor

Note: All `<variable>` notation in this lab should be interpretted as being taken from the Environment file.

### Pave Pivotal Application Service Infrastructure

In this section we will use Terraform to pave the infrastructure necessary for Pivotal Application Service. Upon completion you will have all VNet resources deployed to your <network_rg> and all PAS components deployed to your <pas_rg>.

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

### Configure DNS Zone

In your PAS Resource Group you now have an Azure DNS Zone that holds DNS records for all the PAS components. Let's set up the NS record in the parent Zone to have DNS lookup request routed to your Azure DNS Zone.

1. Get the list of nameservers from your Azure DNS Zone and give this to your lab instructor to have them add your Zone to the parent zone.
```
az network dns zone show -g <envName> -n <envName>.<dnsSuffix>
```
1. Validate that your DNS Zone is configured correctly. Compare the NS Lookup result to the record in the DNS Zone for `apps.sys.<envName>.<dnsSuffix>`. (You can find the DNS Zone in the Azure Portal under `Resource Groups > <envName> > <envName>.<dnsSuffix>`)
```
nslookup <envName>.<dnsSuffix>
```

Before continuing on let's also add a DNS record for your opsman VM.

1. Lookup the ip address of your opsman VM
```
az vm list-ip-addresses -g <envName> -n <envName>-ops-manager-vm
```
1. Create a new A Record in your DNS Zone for the public IP address
```
az network dns record-set a add-record -g <envName> -z <envName>.<dnsSuffix> -n ops -a <public_ip_from_previous_step>
```

### Generate Trusted Certificates

In this section we will generate trusted certificates via Let's Encrypt.

1. [Install Docker](https://docs.docker.com/docker-for-mac/install/)
1. Use docker to run `acme.sh` (Replace values from environment file)
```
export DOMAIN="<envName>.<dnsSuffix>"
sudo mkdir -p acme-workspace/{config,work,logs}
sudo docker run \
  -v "$(pwd)/acme-workspace:/acme.sh" \
  -e "AZUREDNS_SUBSCRIPTIONID=<subscription>" \
  -e "AZUREDNS_TENANTID=<tenant>" \
  -e "AZUREDNS_APPID=<clientId>" \
  -e "AZUREDNS_CLIENTSECRET=<clientSecret>" \
  neilpang/acme.sh --issue --dns dns_azure \
  -d "$DOMAIN" \
  -d "ops.$DOMAIN" \
  -d "harbor.$DOMAIN" \
  -d "*.sys.$DOMAIN" \
  -d "*.apps.$DOMAIN" \
  -d "*.mesh.apps.$DOMAIN" \
  -d "*.login.sys.$DOMAIN" \
  -d "*.uaa.sys.$DOMAIN"
```

### Configure Bosh Director

In this section we will configure Bosh Director in our new foundation.

1. Navigate to Operations Manager `https://ops.<envName>.<dnsSuffix>`
1. Select `Internal Authentication`
1. Give values for `Username`, `Password` and `Decryption Passphrase`
1. Agree to the Terms and Conditions and click `Setup Authentication`
1. Log In to Opsman with the Username and Password supplied
1. Click on the Bosh Director Tile to begin configuration

#### Azure Config

1. Generate a new SSH Key, when prompted do not provide a password.
```
ssh-keygen -t rsa -b 4096 -f id_rsa
```
1. Configure all the values. (Angle brackets are variables from the env file unless otherwise indicated, `$(...)` notation is the output of the command in parenthesis)
```
Subscription ID: <subscription>
Tenant ID: <tenant>
Application ID: <clientId>
Client Secret: <clientSecret>
Resource Group Name: <pas_rg>
BOSH Storage Account Name: $(terraform output bosh_root_storage_account)
SSH Public Key: $(cat id_rsa.pub)
SSH Private Key: $(cat id_rsa)
```
1. Click `Save`

#### Director Config

1. Configure all the values
```
NTP Servers (comma delimited): 0.us.pool.ntp.org
Enable VM Resurrector Plugin: X
Enable Post Deploy Scripts: X
Enable bosh deploy retries: X
Skip Director Drain Lifecycle: X
Store BOSH Job Credentials on tmpfs (beta): X
Keep Unreachable Director VMs: X
```
1. Click `Save`

#### Create Networks

1. Click `Add Network` and fill out the details for the `infrastructure` network
```
Name: infrastructure
Azure Network Name: <network_rg>/<envName>-virtual-network/<envName>-infrastructure-subnet
CIDR: $(az network vnet show -g <network_rg> -n <envName>-virtual-network | jq '.subnets[] | select(.name == "<envName>-infrastructure-subnet") | .addressPrefix' -r)
Reserved IP Ranges: <first 9 addresses starting at 1 from CIDR>
DNS: 168.63.129.16
Gateway: <.1 address from CIDR>
```
1. Click `Add Network` and fill out the details for the `pas` network
```
Name: pas
Azure Network Name: <network_rg>/<envName>-virtual-network/<envName>-pas-subnet
CIDR: $(az network vnet show -g <network_rg> -n <envName>-virtual-network | jq '.subnets[] | select(.name == "<envName>-pas-subnet") | .addressPrefix' -r)
Reserved IP Ranges: <first 9 addresses starting at 1 from CIDR>
DNS: 168.63.129.16
Gateway: <.1 address from CIDR>
```
1. Click `Add Network` and fill out the details for the `services` network
```
Name: pas
Azure Network Name: <network_rg>/<envName>-virtual-network/<envName>-services-subnet
CIDR: $(az network vnet show -g <network_rg> -n <envName>-virtual-network | jq '.subnets[] | select(.name == "<envName>-services-subnet") | .addressPrefix' -r)
Reserved IP Ranges: <first 9 addresses starting at 1 from CIDR>
DNS: 168.63.129.16
Gateway: <.1 address from CIDR>
```
1. Click `Save`

#### Assign AZs and Networks

1. Select `zone-1` for `Singleton Availability Zone`
1. Select `infrastructure` for `Network`
1. Click `Save`

#### Security

1. Because we are using Let's Encrypt Certificates we need to add the Let's Encrypt Root Certificate to the list of `Trusted Certificates`. Find the certificate on the [Chain of Trust](https://letsencrypt.org/certificates/) page of the Let's Encrypt website. Currently the certificate content you should use can be found [here](https://letsencrypt.org/certs/isrgrootx1.pem.txt).
1. Select `Include OpsManager Root CA in Trusted Certs`
1. Click `Save`

#### (Optional) Resource Config

1. Set `Master Compilation Job` > `Instances` to `16`
1. Click `Save`

#### Apply Changes

1. Click on `Installation Dashboard`
1. Click `Review Pending Changes`
1. Click `Apply Changes`


## Additional Tooling

This section contains instructions for how to set up environments and tear them down when instructing this lab content.

### Pre-requisite: Set up student environment 

1. Set the `ENV_NAME`, `LOCATION` and `DNS_SUFFIX` variables and run the `create-pas-infra.sh` script.
1. Give `${ENV_NAME}.env.json` file to students

### Cleanup: Tear down student environment

1. Set the `ENV_FILE` variable to the `${ENV_NAME}.env.json` file and run the `cleanup-pas-infra.sh` script 

