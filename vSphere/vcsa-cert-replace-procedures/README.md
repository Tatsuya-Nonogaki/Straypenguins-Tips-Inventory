# vCSA Certificate Replacement Procedures

## What this project is for

This sub-folder in the [Straypenguin's Tips Inventory](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory) focuses on VMware vSphere certificate management procedures, specifically for vCenter Server Appliance (vCSA).
VMware (Broadcom) has more than two tools to maintain certificates on vCSA;

- **[vCert](https://knowledge.broadcom.com/external/article/385107)** - The main script is `vCert.py`, which is interactive certificate management tool. Recently released
- **[fixcerts.py](https://knowledge.broadcom.com/external/article?legacyId=90561)** - Command-line certificate replacement utility, previously released and officially depricated (but useable!)
- **certificate-manager** - The built-in utility for managing certificates on vCSA

This project organizes and streamlines the procedures for renewing the different certificates, selectively using `vCert` and `fixcerts.py`.

---

## Contents Summary

### 📋 vcsa-cert-replace-procedures.md
Comprehensive step-by-step procedures for renewing and replacing vCSA certificates:

Key features include:
- Pre-renewal and post-renewal checklists
- Detailed troubleshooting guidance
- Service health verification procedures
- Best practices and safety recommendations
- **Note:** This project doesn't deal with custom CA signed certificates, at the time being.

### 📊 vcsa-cert-list-chart.md
Essential reference materials containing:
- Certificate type mappings across different tools
- Store and alias name correlations
- Tool-specific operation commands
