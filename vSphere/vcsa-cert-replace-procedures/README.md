# vCSA Certificate Replacement Procedures

## What this project is for

This sub-folder in the [Straypenguin's Tips Inventory](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory) provides practical, field-tested guidance for managing and renewing certificates in VMware vSphere environments (vCSA/PSC).

It is specifically focused on scenarios where you use Broadcom/VMware’s supported tools—**vCert.py** and **fixcerts.py**—to keep your platform secure and operational.  
The procedures and reference materials here are intended to assist system engineers and administrators in planning, executing, and troubleshooting certificate replacement tasks in real-world environments.

> **Note:** This project currently focuses on VMCA-signed certificates, not custom CA-signed deployments.

VMware (Broadcom) provides several tools to maintain certificates on vCSA:

- **[vCert](https://knowledge.broadcom.com/external/article/385107)** – The recommended, interactive certificate management tool (`vCert.py`), supporting comprehensive renewal operations, validation, and trust anchor management.
- **[fixcerts.py](https://knowledge.broadcom.com/external/article?legacyId=90561)** – A legacy but still usable CLI utility for targeted certificate replacement, officially deprecated but still referenced for certain advanced cases.
- **certificate-manager** – The built-in vCSA utility for basic certificate operations.

This project organizes and streamlines procedures for renewing the various certificate types, including best practices for backup, verification, and troubleshooting.

Unlike typical “happy path” guides, these procedures are built with resilience and flexibility in mind:  
Whenever a tool encounters an error or limitation, the documentation offers clear failover steps—switching to alternative tools, diagnosing with logs, or rolling back safely.  
This makes it especially valuable for system engineers and administrators operating in real production environments, where flexibility and troubleshooting are essential.

---

## Contents Summary

### 📋 vcsa-cert-replace-procedures.md
**Step-by-step, actionable procedures** for vCSA certificate replacement and renewal:
- Detailed operational checklists (pre-renewal and post-renewal)
- Safety and backup recommendations to minimize risk
- Troubleshooting advice and log locations for root cause analysis
- Guidance on proper use of vCert.py and fixcerts.py, including tool limitations, caveats, and failovers between tools
- Service health verification and recovery procedures
- Notes on trust anchors and thumbprints to maintain service connectivity

### 📊 vcsa-cert-list-chart.md
**Reference tables and mappings** for certificate management:
- Clear cross-references of certificate types across vSphere tools, UIs, and CLI aliases (vecs-cli, vSphereClient, fixcerts.py, vCert.py)
- Operation mappings for each certificate type and tool, enabling quick lookup of correct procedures and arguments
- Menu and argument guides for vCert.py, based on real-world usage
- Designed for rapid field reference
