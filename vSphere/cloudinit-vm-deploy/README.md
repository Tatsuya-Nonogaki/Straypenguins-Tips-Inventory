# Cloud-init Ready: Linux VM Deployment Kit on vSphere

Automated, repeatable deployment of cloud-init-enabled Linux VMs on vSphere, using PowerShell/PowerCLI and custom seed ISO generation.

---

## Features

- **Three-phase deployment workflow:** Template Clone, Guest Preparation, Cloud-init Personalization
- **Parameter-driven, YAML-based configuration** for per-VM customization
- **Robust cloud-init integration:** hostname, users, SSH keys, network, `/etc/hosts`, and more
- **Safety by design:** Template VM protected from accidental cloud-init runs
- **Compatible with RHEL9** (and derivatives), designed for vSphere 7/8 and Windows Server 2019+ admin hosts
- **Cross-platform:** PowerShell/PowerCLI for Windows, Linux guest scripts, and standard cloud-init

---

## Quick Start

### 1. Preparation

#### On the Template VM (RHEL9)

- **Install required packages:**
    ```sh
    sudo dnf install cloud-init cloud-utils-growpart
    ```
    💡 See `infra/req-pkg-cloudinit.txt` for the package list.

- **Prevent accidental cloud-init runs:**  
    Use the helper script to install all infra files and block cloud-init on the template:
    ```sh
    cd infra/
    sudo ./prevent-cloud-init.sh
    ```
    This will:
    - Create `/etc/cloud/cloud-init.disabled` (prevents cloud-init auto-execution)
    - Overwrite `/etc/cloud/cloud.cfg` with the optimized configuration
    - Place `/etc/cloud/cloud.cfg.d/99-template-maint.cfg`

- **Clean up previous cloud-init artifacts, if any.**
- **Shutdown and convert to a Template VM** in vSphere.

#### On the Windows Admin Host

- **Install [PowerCLI](https://developer.vmware.com/powercli)** (v13.3+ recommended)
- **Install [powershell-yaml](https://github.com/cloudbase/powershell-yaml)** module
- **Download or clone this repository**  
- **Install `mkisofs.exe`** (from [cdrtfe](https://sourceforge.net/projects/cdrtfe/)) and place as specified in the script's `$mkisofs` path

---

### 2. Prepare Parameter and Template Files

- **Create per-VM parameter file:**  
  Copy `params/vm-settings_example.yaml` → `params/<your-vm>.yaml` and edit for your VM's resources, network, and cloud-init needs.
    - All VM settings (vCenter, hardware, OS, cloud-init) are managed here.
    - **(Important)** Use CRLF (Windows) for this file.

- **Edit cloud-init template files as needed:**  
  Copy `templates/original/*_template.yaml` to `templates/`, and update for your site:
    - `user-data_template.yaml`
    - `meta-data_template.yaml`
    - `network-config_template.yaml`
    - **(Important)** These files must use LF (Linux) line endings.

- **(Advanced)** Edit `infra/cloud.cfg` or `infra/99-template-maint.cfg` only if you need to customize template/clone-level cloud-init behavior.

---

### 3. Run the Deployment Script

In a PowerShell terminal, from the repository root:

```powershell
.\cloudinit-linux-vm-deploy.ps1 -Phase 1,2,3 -Config .\params\<your-vm>.yaml
```

- You may run phases separately (`-Phase 1`, `-Phase 2`, `-Phase 3`) if needed.
- The script will:
    1. Clone the Template VM as specified
    2. Prepare the guest (clean cloud-init, set config, enable cloud-init)
    3. Generate and attach a cloud-init seed ISO, then boot the VM to personalize with cloud-init

---

### 4. Confirm and Finalize

- The deployed VM should boot, apply all cloud-init configuration, and be ready for use.
- Check logs in the `spool/<VMNAME>/` directory on the admin host and `/var/log/cloud-init*.log` files in the guest if troubleshooting is needed.

---

## Directory Structure

```
/
├── cloudinit-linux-vm-deploy.ps1
├── params/
│   ├── vm-settings_example.yaml
│   └── <your copy of above>
├── templates/
│   ├── <your copies of *_template.yaml>
│   └── original/
│       ├── user-data_template.yaml
│       ├── meta-data_template.yaml
│       └── network-config_template.yaml
├── scripts/
│   └── init-vm-cloudinit.sh
├── infra/
│   ├── cloud.cfg
│   ├── 99-template-maint.cfg
│   ├── enable-cloudinit-service.sh
│   ├── prevent-cloud-init.sh
│   ├── req-pkg-cloudinit.txt
│   └── req-pkg-cloudinit-full.txt
└── spool/
    └── <VMNAME>/
```

---

## Notes & Recommendations

- **/etc/hosts Customization:**  
  The kit uses `write_files` in cloud-init user-data to fully control `/etc/hosts` for each VM.  
  `manage_etc_hosts: false` is automatically set at clone-init to avoid conflict.

- **Cloud-init Safety:**  
  The Template VM is protected from all cloud-init actions (`cloud-init.disabled` and config files).  
  Clones automatically remove the protection and enable cloud-init on their first boot.

- **Line Endings:**  
  - `cloudinit-linux-vm-deploy.ps1` and `vm-settings*.yaml`: **CRLF** (Windows)
  - All other scripts and YAML templates: **LF** (Linux)

- **Multi-NIC/Advanced:**  
  Edit `cloud.cfg` and templates as needed for advanced configurations.

- **PowerCLI** and **powershell-yaml** modules are required on the admin host.

- **mkisofs.exe** must be available as specified in the script.

---

## Troubleshooting

- **Cloud-init did not run?**  
  - Confirm that `/etc/cloud/cloud-init.disabled` was removed in the clone.
  - Check that seed ISO was attached and contained the correct user-data/meta-data.

- **VM customization failed?**  
  - Review `spool/<VMNAME>/deploy-*.log` and guest `/var/log/cloud-init*.log`.

- **Line ending errors?**  
  - YAML templates used by cloud-init must be LF (Linux).  
    PowerShell/param files should be CRLF (Windows).

---

## References

- [cloud-init documentation](https://cloud-init.io/)
- [VMware PowerCLI](https://developer.vmware.com/powercli)
- [powershell-yaml](https://github.com/cloudbase/powershell-yaml)
- [cdrtfe (mkisofs win32)](https://sourceforge.net/projects/cdrtfe/)

---

## License

This project is licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.
