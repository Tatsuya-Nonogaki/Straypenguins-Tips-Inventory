# Cloud-init Ready: Linux VM Deployment Kit on vSphere

Automated, repeatable deployment of cloud-init-enabled Linux VMs on vSphere, using PowerShell/PowerCLI and custom seed ISO generation.

---

## 🧭 Features

- **Four-phase deployment workflow:** Template Clone, Guest Preparation, Cloud-init Personalization, and cloud-init disablement
- **Parameter-driven, YAML-based configuration** for per-VM customization
- **Robust cloud-init integration:** hostname, users, SSH keys, network, `/etc/hosts`, and more
- **Template safety:** Template VM is protected from accidental cloud-init runs
- **Compatible with RHEL9** (and derivatives), designed for vSphere 7/8 and Windows Server 2019+ admin hosts
- **Cross-platform:** PowerShell/PowerCLI for Windows, Linux guest scripts, and standard cloud-init

---

## 🚀 Quick Start

### 1. Preparation

#### On the Windows Admin Host or Any PC

- **Download or clone this repository**  
- Copy the `infra/` directory to the Template VM.

#### On the Template VM (RHEL9)

- **Ensure the template VM has at least one CD drive:**  
    Cloud-init deployment requires a CD drive on the cloned VM to load the seed ISO.

- **Ensure VMware Tools (open-vm-tools) is installed:**
    ```sh
    sudo dnf install open-vm-tools
    ```

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
  You can safely run `cloud-init clean` to remove any old instance state here on the Template VM.

- **Shut down and convert to a VM Template** in vSphere.

#### On the Windows Admin Host

- **Install [PowerCLI](https://developer.vmware.com/powercli)** (v13.3+ recommended)
- **Install [powershell-yaml](https://github.com/cloudbase/powershell-yaml)** module
- **Ensure `mkisofs.exe` is available** (from [cdrtfe](https://sourceforge.net/projects/cdrtfe/)) and placed according to the script's `$mkisofs` path. See [Notes & Recommendations](#notes--recommendations) for alternatives.
- **Download or clone this repository**  

---

### 2. Prepare Parameter and Template Files

- **Create per-VM parameter file:**  
  Copy `params/vm-settings_example.yaml` → `params/vm-settings_<VMNAME>.yaml` (any name you prefer) and edit for your VM's resources, network, and cloud-init needs.
    - All VM settings (vCenter, hardware, OS, cloud-init) are managed here.
    - ⚠️ **Important:** Use CRLF (Windows) line endings for this file.

- **Edit cloud-init template files as needed:**  
  Copy `templates/original/*_template.yaml` to `templates/`, and update for your site:
    - `user-data_template.yaml`
    - `meta-data_template.yaml`
    - `network-config_template.yaml`
    - ⚠️ **Important:** These files must use LF (Linux) line endings.

- **(Advanced)** Edit `infra/cloud.cfg` or `infra/99-template-maint.cfg` only if you need to customize template/clone-level cloud-init behavior.

---

### 3. Run the Deployment Script

- Create `spool` folder on the repository root to save logs and seed ISO and its source files.

- Open a PowerShell terminal in the repository root and run:

  ```powershell
  .\cloudinit-linux-vm-deploy.ps1 -Phase 1,2,3 -Config .\params\vm-settings_<VMNAME>.yaml
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

## 🗂️ Directory Structure

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

## 📝 Notes & Recommendations

- **/etc/hosts Customization:**  
  The kit uses `write_files` in cloud-init user-data to fully control `/etc/hosts` for each VM.  
  `manage_etc_hosts: false` is automatically set during clone-init to avoid conflicts.

- **Template and Clone Safety:**  
  The Template VM is fully protected from cloud-init (`cloud-init.disabled` and config files).  
  Clones automatically remove this protection and enable cloud-init on first boot.

- **Line Endings:**  
  - `cloudinit-linux-vm-deploy.ps1` and `vm-settings*.yaml`: **CRLF** (Windows)
  - All other scripts and YAML templates: **LF** (Linux)

- **Multi-NIC/Advanced:**  
  Edit `cloud.cfg` and templates as needed for advanced configurations.

- **PowerCLI** and **powershell-yaml** modules are required on the admin host.

- **mkisofs.exe** must be available as specified in the script.  
    Alternatives such as `genisoimage` (e.g., under WSL2 on Windows Server 2022/Windows 11) are supported if you adjust `$mkisofs` and related script variables accordingly.

- **Disk Parameters:**  
  You may omit the `disk_format:` and/or the `disks:` parameter (in whole or in part) from your parameter YAML file if you do not wish to change disk provisioning type or disk sizes for some or all disks, as already defined in the template VM.  
  In this case, the cloned VM will inherit the disk settings for the omitted items from the template as-is.

---

## 🛠️ Troubleshooting

- **Cloud-init did not run?**  
  - Confirm that `/etc/cloud/cloud-init.disabled` was removed in the clone.
  - Check that the seed ISO was attached and contains the correct user-data/meta-data. The ISO and its source files are stored in the `spool/<your_vm>/` directory.

- **VM customization failed?**  
  - Review `spool/<VMNAME>/deploy-*.log` and guest `/var/log/cloud-init*.log` for details.

- **Template VM not found or cannot be used as a template?**  
  - Have you converted the source VM to a vSphere Template?  
    The deployment script expects the master VM to be in Template state.  
    If you see errors such as "Template not found" or related deployment failures, confirm that your VM has been converted to a Template via the vSphere Web UI before running the script.

- **Line ending errors?**  
  - YAML templates for cloud-init must use **LF** (Linux).
  - PowerShell and parameter files must use **CRLF** (Windows).

---

## 👉 References

- [cloud-init documentation](https://cloud-init.io/)
- [VMware PowerCLI](https://developer.vmware.com/powercli)
- [powershell-yaml](https://github.com/cloudbase/powershell-yaml)
- [cdrtfe (mkisofs win32)](https://sourceforge.net/projects/cdrtfe/)

---

## License

This project is licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.
