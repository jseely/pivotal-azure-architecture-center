#!/usr/bin/env bash
set -eux

ENVIRONMENT=$(cat $ENV_FILE | jq '.' -c)

az group delete -n $(echo $ENVIRONMENT | jq '.pas_rg' -r) -y
az group delete -n $(echo $ENVIRONMENT | jq '.network_rg' -r) -y
az ad app delete --id $(echo $ENVIRONMENT | jq '.clientId' -r) 

rm $ENV_FILE
