# Terraform Azure VM for Jenkins
This repository include terraform script for deploying Jenkins on Azure.

# How to run
Before run terraform script for deploying VM, an attribute for password on main.tf should be changed. This password is used for login into VM which will be installed Jenkins. Please refer to the [requirement](https://docs.microsoft.com/en-us/azure/virtual-machines/linux/faq#what-are-the-password-requirements-when-creating-a-vm) for password you will use.
```
admin_password = "CHANGE_ME"
```
Then, run...
```
az login
terraform init
terraform apply
```