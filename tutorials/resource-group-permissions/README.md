# Exploring Resource Groups and Permissions

In this lab exercise you will examine the permissions you have on resources in a resource group. The instructor of this lab has created a resource group for you in their Azure subscription and assigned you "Owner" permissions.

## Logging In

Log in to your Azure account.

```
az login
```

This should open a browser window to proceed with logging in. When you finish logging in you should see a JSON array with containing all the subscriptions in which you have permissions over contained resources. One of these should be your instructor's subscription. Select it with the following command.

```
az account set --subscription <instructor_subscription_id>
```

## Explore Your Permissions

Check if you have any permissions over the subscription.

```
az role assignment list --scope /subscriptions/<instructor_subscription_id> #Note: This command defaults to the currently selected subscription.
```

You should see an empty array, showing you have no subscription wide permissions.

Let's now see if we have any permissions over resource groups within this subscription.

```
az role assignment list --include-groups
```

You should see at least one entry scoped to `/subscriptions/<instructor_subscription_id>/resourcegroups/<your_alias>-rg-permissions`. The `Owner` role should have been assigned under the `roleDefinitionName`, this gives you full control over this resource group allowing you to create/modify/delete resources in this group as well as delegate permissions to other principals.

## Service Accounts

When you get into IaaS automation, it is common to delegate `Contributor` permissions over a Resource Group to a Service Principal giving an automated agent the ability to create/modify/delete resources to operate a system.

Register your application to manage this resource group.

```
az ad app create --display-name <your_alias>-rp-permissions-sp --password <sp_password>
```

Create a Service Principal for the application. You will need the Application Id that is returned as part of the previous command (`appId`).

```
az ad sp create --id <app_id>
```

Assign `Contributor` role over your Resource Group to your new Service Principal.

```
az role assignment create --assignee <app_id> --role Contributor --scope /subscriptions/<instructor_subscription_id>/resourcegroups/<your_alias>-rg-permissions
```

To validate that your Service Principal has the correct permissions log in to the Azure CLI using your Application Id and Password and ensure that you have the `Contributor` role over the Resource Group.

```
az login --service-principal --username <application_id> --password <sp_password>
az role assignment list --all
```

You should get back the role assignment from the previous step.
