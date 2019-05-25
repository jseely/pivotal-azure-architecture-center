#!/usr/bin/env bash
set -eux

for student in $(echo $STUDENT_LIST | tr ";" "\n")
do
  stu_alias=$(echo $student | cut -f1 -d:)
  stu_email=$(echo $student | cut -f2 -d:)

  # Create the resource group
  rg_name="${stu_alias}-rg-permissions"
  az group create -n $rg_name -l westus2

  # Assign student the "Owner" role over resource group
  az role assignment create --assignee "${stu_email}" --role Owner -g $rg_name
done 
