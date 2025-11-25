# Cloud-init Ready: Linux VM Deployment Kit on vSphere

## 🧭 Overview

This kit is designed to enable quick deployment of Linux VMs from a **well-prepared** (not an out-of-the-box default) VM Template on vSphere, using the cloud-init framework. The main control program is a PowerShell script: `cloudinit-linux-vm-deploy.ps1`. The workflow is split into four phases:

- **Phase 1:** Create a clone from a VM Template  
- **Phase 2:** Prepare the clone to accept cloud-init  
- **Phase 3:** Generate a cloud-init seed (user-data, meta-data, optional network-config), pack them into an ISO, upload it to a datastore and attach it to the clone's CD drive, then boot the VM and wait for cloud-init to complete  
- **Phase 4:** Detach and remove the seed ISO from the datastore, then place `/etc/cloud/cloud-init.disabled` on the guest to prevent future automatic personalization (can be skipped with `-NoCloudReset`)

## 🚚 Project has moved! 🚧 ➔ Its own repository: [cloudinit-vm-deploy](https://github.com/Tatsuya-Nonogaki/cloudinit-vm-deploy)

The **cloudinit-vm-deploy** kit was one of the topics in this Tips Inventory. It has now moved to its own repository:

https://github.com/Tatsuya-Nonogaki/cloudinit-vm-deploy

The new repository holds the full source, templates, examples, and documentation. This README retains only a brief notice and pointer — please visit the new repo for the complete project and up-to-date instructions. Awaiting your visit!
