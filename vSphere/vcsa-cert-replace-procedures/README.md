# vCSA Certificate Replacement Procedures

## What this project is for

This sub-folder focuses on VMware vSphere certificate management procedures, specifically for vCenter Server Appliance (vCSA).
VMware (Broadcom) has more than two tools for maintain certificates on vCenter Server Appliance (vCSA);
- **vCert** - The main script is `vCert.py`, which is interactive certificate management tool. Recently released
- **fixcerts.py** - Command-line certificate replacement utility, previously released and officially depricated (but useable!)
- **certificate-manager** - Standard utility to manage certificates on vCSA
This project summarize the procedures to renew the certificates using `vCert` and `fixcerts.py`.

---

## Contents Summary

### 📋 vcsa-cert-replace-procedures.md
Comprehensive step-by-step procedures for renewing and replacing vCSA certificates using:

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

