#!/usr/bin/env bash
set -eux

for student in $(echo $STUDENT_LIST | tr ";" "\n")
do
  stu_alias=$(echo $student | cut -f1 -d:)
  stu_email=$(echo $student | cut -f2 -d:)

  # Create the resource group
  rg_name="${stu_alias}-rg-permissions"
  az group delete -n $rg_name -y
done 
