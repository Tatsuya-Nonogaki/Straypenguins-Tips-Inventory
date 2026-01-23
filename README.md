# [Straypenguin's Tips Inventory](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory)

## What this project is for

This repository serves as a comprehensive technical knowledge base and documentation inventory, containing practical procedures, troubleshooting guides, and reference materials for various IT infrastructure and system administration tasks. The project aims to collect and organize actionable technical documentation that can be readily used by system administrators, engineers, and IT professionals.

---

## 🧭 Table of Contents
- 🖥️ [vSphere](#%EF%B8%8F-vsphere)
- 🐧 [Linux](#-linux)
- ☕ [WebLogic](#-weblogic)
- 🐙 [GitHub](#-github)

---

## 🖥️ [vSphere](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory/tree/main/vSphere)
Procedures and Tools for administration:

- [vCSA Certificate Replacement](vSphere/vcsa-cert-replace-procedures/README.md) *(GitHub Web)* / [*(GitHub Pages HTML)*](https://tatsuya-nonogaki.github.io/Straypenguins-Tips-Inventory/vSphere/vcsa-cert-replace-procedures/)  
   This sub-folder focuses on VMware vSphere certificate management procedures, specifically for vCenter Server Appliance (vCSA).  
   This project organizes and streamlines the procedures for renewing the different certificates, selectively using `vCert` and `fixcerts.py`.
- [Cloud-init Ready: Linux VM Deployment Kit on vSphere](vSphere/cloudinit-vm-deploy/README.md) *(GitHub Web)* / [*(GitHub Pages HTML)*](https://tatsuya-nonogaki.github.io/Straypenguins-Tips-Inventory/vSphere/cloudinit-vm-deploy/)  
   This kit enables quick deployment of Linux VMs from a prepared VM Template on vSphere, using the cloud-init framework. The main control program is a PowerShell script: `cloudinit-linux-vm-deploy.ps1`; workflow is split into four phases for ease of check, rerun and debug.

## 🐧 [Linux](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory/tree/main/Linux)
System administration and security:

- [OpenSSL](Linux/OpenSSL/) *(GitHub Web)* / [*(GitHub Pages HTML)*](https://tatsuya-nonogaki.github.io/Straypenguins-Tips-Inventory/Linux/OpenSSL/)
  - Provides several simple utility scripts for OpenSSL
- [SELinux](Linux/SELinux/) *(GitHub Web)* / [*(GitHub Pages HTML)*](https://tatsuya-nonogaki.github.io/Straypenguins-Tips-Inventory/Linux/SELinux/)
  - [Manage SELinux to Allow httpd to Access Port 7003/TCP](Linux/SELinux/selinux-mod_wl-allow-httpd-7003.md)
  - [Create SELinux Policy Module for Your Own Service](Linux/SELinux/selinux-create-own-service-policy.md)
  - [SELinux Policy Troubleshooting: Resolving Audit Denials for a Custom Service](Linux/SELinux/selinux-service-policy-troubleshooting.md)
- [Miscellaneous Research](Linux/Misc)
  - [Configure Samba Server on RHEL9](Linux/Misc/samba-settings.md) *(GitHub Web)* / [*(GitHub Pages HTML)*](https://tatsuya-nonogaki.github.io/Straypenguins-Tips-Inventory/Linux/Misc/samba-settings.html)
- [Reliably Update RHEL](Linux/update-rhel/howto-reliably-update-rhel.md) *(GitHub Web)* / [*(GitHub Pages HTML)*](https://tatsuya-nonogaki.github.io/Straypenguins-Tips-Inventory/Linux/update-rhel/howto-reliably-update-rhel.html)

## ☕ [WebLogic](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory/tree/main/WebLogic)
[Automation & Configuration Snippets for Administrators](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory/tree/main/WebLogic) *(GitHub Web)* / [*(GitHub Pages HTML)*](https://tatsuya-nonogaki.github.io/Straypenguins-Tips-Inventory/WebLogic/)

- [Automation WLST](WebLogic/automation-wlst/)
- [profile.d](WebLogic/profile.d/)
- [systemd](WebLogic/systemd/)
- [rsyslog](WebLogic/rsyslog/)
- [Miscellaneous base setting tools](WebLogic/)

## 🐙 [GitHub](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory/tree/main/GitHub)
[GutHub Operation Tips Memorandum](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory/tree/main/GitHub) *(GitHub Web)* / [*(GitHub Pages HTML)*](https://tatsuya-nonogaki.github.io/Straypenguins-Tips-Inventory/GitHub/)

- [Merge devel to main While Keeping the Branch History Clean](GitHub/merge_devel_to_main_clean_history.md)
- [Creating and Maintaining a Pull Request Branch](GitHub/create_maintain_pr_branch.md)
- [GitHub Pages + Jekyll: How Markdown Links Are Handled](GitHub/github-pages-md-link-behavior.md)
- [UTF-8 Emoji Copy-Paste Sheet](GitHub/emoji-utf8.md)

---

## Getting Started
Navigate to the relevant technology folder to access specific documentation or tools. For more details, please consult the README on each folder.

---

*This inventory is actively maintained and will be expanded with additional technical procedures and reference materials as they become available.*
