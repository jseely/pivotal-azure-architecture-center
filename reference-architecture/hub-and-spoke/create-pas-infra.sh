#!/usr/bin/env bash
set -eux

# Create SP and RG for Environment
export current_subscription=$(az account list | jq '.[] | select(.state == "Enabled")' -c)
export subscription_id=$(echo $current_subscription | jq '.id' -r)
export client_secret=$(LC_CTYPE=C tr -dc "a-zA-Z0-9" < /dev/urandom | head -c 16)
export storageAccountPrefix=$(LC_CTYPE=C tr -dc "a-z" < /dev/urandom | head -c 10)
export app=$(az ad app create --display-name "$ENV_NAME-sp" --password "$client_secret" | jq '.' -c)
export appId=$(echo $app | jq '.appId' -r)
az ad sp create --id "$appId"

sleep 30

az group create -n $ENV_NAME -l $LOCATION
az role assignment create --assignee $appId --role Owner --scope "/subscriptions/$subscription_id/resourcegroups/$ENV_NAME"

# Deploy Network RG
NETWORK_RG="$ENV_NAME-network"
az group create -n "$NETWORK_RG" -l $LOCATION
az role assignment create --assignee $appId --role Owner --scope "/subscriptions/$subscription_id/resourcegroups/$NETWORK_RG"

ENVIRONMENT="{\"envName\": \"${ENV_NAME}\", \"clientId\": \"${appId}\", \"clientSecret\": \"${client_secret}\", \"subscription\": \"${subscription_id}\", \"tenant\": \"$(echo $current_subscription | jq -r '.tenantId')\", \"network_rg\": \"${NETWORK_RG}\", \"pas_rg\": \"${ENV_NAME}\", \"storageAccountPrefix\": \"${storageAccountPrefix}\", \"location\": \"${LOCATION}\", \"dnsSuffix\": \"${DNS_SUFFIX}\"}"
echo $ENVIRONMENT | jq '.' > $ENV_NAME.env.json


# Create VNet
az network vnet create --name vnet \
  --resource-group $NETWORK_RG --location $LOCATION \
  --address-prefixes 10.0.0.0/16

#az network vnet subnet create --name infra \
#  --vnet-name pcf-vnet \
#  --resource-group $NETWORK_RG \
#  --address-prefix 10.0.4.0/26 
#az network vnet subnet create --name pas \
#  --vnet-name pcf-vnet \
#  --resource-group $NETWORK_RG \
#  --address-prefix 10.0.12.0/22 
#az network vnet subnet create --name services \
#  --vnet-name pcf-vnet \
#  --resource-group $NETWORK_RG \
#  --address-prefix 10.0.8.0/22 

