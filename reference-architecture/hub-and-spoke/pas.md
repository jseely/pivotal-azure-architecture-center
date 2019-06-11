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
    git clone https://github.com/jseely/terraforming-azure.git
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
    vm_admin_username = "ubuntu"

    create_vnet = false
    pcf_vnet_name   = "vnet"
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
    nslookup apps.sys.<envName>.<dnsSuffix>
    ```

#### Before continuing on let's also add a DNS record for your opsman VM.

1. Lookup the ip address of your opsman VM
    ```
    az vm list-ip-addresses -g <envName> -n <envName>-ops-manager-vm
    ```
1. Create a new A Record in your DNS Zone for the public IP address
    ```
    az network dns record-set a add-record -g <envName> -z <envName>.<dnsSuffix> -n ops -a <public_ip_from_previous_step>
    ```

### Update OpsMan VM SSH Key

1. Generate a new SSH Key, when prompted do not provide a password.
    ```
    ssh-keygen -t rsa -b 4096 -f id_rsa
    ```
1. Update the SSH key used for authentication on the Opsman VM
    ```
    az vm user update -u ubuntu --ssh-key-value "$(cat id_rsa.pub)" -n <envName>-ops-manager-vm -g <envName>
    ```

### Generate Trusted Certificates

In this section we will generate trusted certificates via Let's Encrypt.

1. [Install Docker](https://docs.docker.com/docker-for-mac/install/)
1. Use docker to run `acme.sh` (Replace values from environment file)
    ```
    export DOMAIN="<envName>.<dnsSuffix>"
    mkdir -p acme-workspace/{config,work,logs}
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
1. Your certs can be found in the `acme-workspace/<envName>.<dnsSuffix>` directory.

### Configure Bosh Director

In this section we will configure Bosh Director in our new foundation.

1. Navigate to Operations Manager `https://pcf.<envName>.<dnsSuffix>`
1. Select `Internal Authentication`
1. Give values for `Username`, `Password` and `Decryption Passphrase`
1. Agree to the Terms and Conditions and click `Setup Authentication`
1. Log In to Opsman with the Username and Password supplied
1. Click on the Bosh Director Tile to begin configuration

#### Azure Config

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
    Azure Network Name: <network_rg>/vnet/<envName>-infrastructure-subnet
    CIDR: $(az network vnet show -g <network_rg> -n vnet | jq '.subnets[] | select(.name == "<envName>-infrastructure-subnet") | .addressPrefix' -r)
    Reserved IP Ranges: <first 9 addresses starting at 1 from CIDR>
    DNS: 168.63.129.16
    Gateway: <.1 address from CIDR>
    ```
1. Click `Add Network` and fill out the details for the `pas` network
    ```
    Name: pas
    Azure Network Name: <network_rg>/vnet/<envName>-pas-subnet
    CIDR: $(az network vnet show -g <network_rg> -n vnet | jq '.subnets[] | select(.name == "<envName>-pas-subnet") | .addressPrefix' -r)
    Reserved IP Ranges: <first 9 addresses starting at 1 from CIDR>
    DNS: 168.63.129.16
    Gateway: <.1 address from CIDR>
    ```
1. Click `Add Network` and fill out the details for the `services` network
    ```
    Name: services
    Azure Network Name: <network_rg>/vnet/<envName>-services-subnet
    CIDR: $(az network vnet show -g <network_rg> -n vnet | jq '.subnets[] | select(.name == "<envName>-services-subnet") | .addressPrefix' -r)
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

### Add Tiles to Operations Manager

1. SSH into the Opsman VM
    ```
    ssh-add id_rsa
    ssh ubuntu@ops.<envName>.<dnsSuffix>
    ```
1. Download the Pivotal Application Service and Microsoft Azure Service Broker Tiles
    ```
    wget -O "pas.tile" --post-data="" --header="Authorization: Token <pivnet_legacy_token>" "https://network.pivotal.io/api/v2/products/elastic-runtime/releases/366062/product_files/378183/download"
    wget -O "masb.tile" --post-data="" --header="Authorization: Token <pivnet_legacy_token>" "https://network.pivotal.io/api/v2/products/azure-service-broker/releases/282392/product_files/294549/download"
    ```
1. Upload the tiles to Opsman
    ```
    uaac target localhost/uaa --skip-ssl-validation
    uaac token owner get opsman <opsman_username> -s "" -p <opsman_password>
    APITOKEN=$(uaac contexts | grep "localhost" -A6 | grep access_token | cut -d ':' -f  2 | cut -d ' ' -f 2)

    curl "https://localhost/api/v0/available_products" -F "product[file]=@pas.tile" -X POST  -H "Authorization: Bearer $APITOKEN" -k -o output --progress-bar
    curl "https://localhost/api/v0/available_products" -F "product[file]=@masb.tile" -X POST  -H "Authorization: Bearer $APITOKEN" -k -o output --progress-bar
    ```

#### Update VM Skus

When you first deploy Operations Manager it comes preconfigured with a number of Azure VM SKUs by default. Azure unfortunately has inconsistent availability of VM SKUs across Regions. In this section we update the VM SKUs available within OpsMan.

1. Install `om` cli
    ```
    brew tap starkandwayne/cf
    brew install om
    ```
1. Get the list of VMs currently configured in Opsman and save it to a new file `vm_types.json`
    ```
    om \
    --skip-ssl-validation \
    --target ops.<envName>.<dnsSuffix> \
    --username <your_opsman_user> \
    --password <your_opsman_password> \
    curl -x GET --path /api/v0/vm_types \
    > vm_types.json
    ```
1. Get the list of available VM SKUs, formatted to Opsman structured VM definitions and save it to a new file `available_vm_types.json`
    ```
    az vm list-sizes -l <location> | jq '{"vm_types": [.[] | {"name": .name, "ram": .memoryInMb, "ephemeral_disk": .resourceDiskSizeInMb, "cpu": .numberOfCores}]}' > available_vm_types.json
    ```
1. Add the VMs from the `available_vm_types.json` that you want to the `vm_types.json`. In `westus2` we should replace all `D_v2` and `DS_v2` with their corresponding `D_v3` and `DS_v3` alternatives.
1. Put the new list of VMs into Opsman
    ```
    om \
    --skip-ssl-validation \
    --target ops.<envName>.<dnsSuffix> \
    --username <your_opsman_user> \
    --password <your_opsman_password> \
    curl -x PUT --path /api/v0/vm_types \
    --data "$(jq -c '.' vm_types.json)"
    ```

### Configure Pivotal Application Service

1. Navigate to Opsman website `https://ops.<envName>.<dnsSuffix>`
1. From the left pane, click the `+` under `Pivotal Application Service`
1. Click on the Pivotal Application Service Tile

#### Assign AZs and Network

1. Select `zone-1` to `Place singleton jobs in`
1. Select `zone-1`, `zone-2` and `zone-3` to `Balance other jobs in`
1. Select under `Network` the `pas` network
1. Click `Save`

#### Domains

1. Fill out the Domains section
    ```
    System Domain: sys.<envName>.<dnsSuffix>
    Apps Domain: apps.<envName>.<dnsSuffix>
    ```
1. Click `Save`

#### Networking

1. Under `Certificates and Private Keys for HAProxy and Router` click `Add`
1. Fill out the information as follows
    ```
    Name: Let's Encrypt Cert
    Certificate PEM: $(cat acme-workspace/<envName>.<dnsSuffix>/fullchain.cer)
    Private Key PEM: $(cat acme-workspace/<envName>.<dnsSuffix>/<envName>.<dnsSuffix>.key)
    ```
1. Set `Certificate Authorities Trusted by Router and HAProxy` to the Let's Encrypt Root CA Cert
1. Select `TLS terminated for the first time at the Router`
1. `Disable` the `HAProxy forwards requests to Router over TLS.` feature
1. Uncheck `Disable SSL certificate verification for this environment`
1. Click `Save`

#### Application Containers

1. Select `Routinely clean up Cell disk-space`
1. `Disable` the NFSv3 volume services feature.
1. Click `Save`

#### Application Security Groups

1. Type `X` in the textbox to Acknowledge that the Application Service administrator team is responsible for setting appropriate Application Security Groups to control application network policy.
1. Click `Save`

#### UAA

1. Fill out `SAML Service Provider Credentials`
    ```
    Certificate PEM: $(cat acme-workspace/<envName>.<dnsSuffix>/fullchain.cer)
    Private Key PEM: $(cat acme-workspace/<envName>.<dnsSuffix>/<envName>.<dnsSuffix>.key)
    ```
1. Click `Save`

#### CredHub

1. Provide an `Encryption Key` by clicking `Add`
  * Set the `Name` of the key
  * Set a `Key` that will be used to encrypt your CredHub information
  * Select the `Primary` checkbox
1. Click `Save`

#### Internal MySQL

1. Set an `E-mail address`, the MySQL service will send alerts when the cluster experiences a replication issue or a node is not allowed to auto-rejoin the cluster.
1. Click `Save`

#### Cloud Controller

1. In the textboxt under `Type "X" to acknowledge that you have no applications running with cflinuxfs2.` type `X`
1. Click `Save`

#### Resource Config

1. Under the `Load Balancers` column set the following values
  * Router: &lt;envName&gt;-web-lb
  * Diego Brain: &lt;envName&gt;-diego-ssh-lb
1. Click `Save`

#### Apply Changes

1. Click `INSTALLATION DASHBOARD`
1. Click `REVIEW PENDING CHANGES`
1. Click `APPLY CHANGES`

### Configure Microsoft Azure Service Broker

1. Navigate to Opsman website `https://ops.<envName>.<dnsSuffix>`
1. From the left pane, click the `+` under `Microsoft Azure Service Broker`
1. Downlaod the `Ubuntu Xenial Stemcell for Azure 170.76` from `https://network.pivotal.io/products/stemcells-ubuntu-xenial#/releases/376271`
1. Back in Opsman go to the `STEMCELL LIBRARY` and on the `Microsoft Azure Service Broker` select `Upload Stemcell` and enable it for that tile
1. Click on the `Microsoft Azure Service Broker` tile on the `INSTALLATION DASHBOARD`

#### Assign AZs and Networks

1. Select `zone-1` under `Place singleton jobs in`
1. Select all three `zone-1`, `zone-2` and `zone-3` under `Balance other jobs in`
1. Under `Network` select `services`
1. Click `Save`

#### Azure Config

1. Fill out the values as follows
    ```
    Subscription Id: <subscription>
    Tenant Id: <tenant>
    Client Id: <clientId>
    Client Secret: <clientSecret>
    ```
1. Click `Save`

#### Broker Config

1. Open in another tab `https://portal.azure.com`
1. Click `Create a Resource` in the top left
1. Search for `SQL Database` and click `Create`
1. Under `Resource Group` select your <envName>
1. Set `Database name` to `masb-db`
1. Under `Server` click `Create new`, fill out and record the details of your new server
1. Click `Review + Create`
1. Click `Create`
1. Go back to Opsman > MASB > Broker Config
1. Fill out all the details based on the details of the SQL Database that you created
1. Create a `Database Encryption Key` and record it somewhere safe
1. Click `Save`

#### Apply Changes

1. Click `INSTALLATION DASHBOARD`
1. Click `REVIEW PENDING CHANGES`
1. Click `APPLY CHANGES`

## Additional Tooling

This section contains instructions for how to set up environments and tear them down when instructing this lab content.

### Pre-requisite: Set up student environment 

1. Set the `ENV_NAME`, `LOCATION` and `DNS_SUFFIX` variables and run the `create-pas-infra.sh` script.
1. Give `${ENV_NAME}.env.json` file to students

### Cleanup: Tear down student environment

1. Set the `ENV_FILE` variable to the `${ENV_NAME}.env.json` file and run the `cleanup-pas-infra.sh` script 

