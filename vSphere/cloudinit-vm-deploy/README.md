# Cloud-init Ready: Linux VM Deployment Kit on vSphere

Automated, repeatable deployment of cloud-init-enabled Linux VMs on vSphere, using PowerShell/PowerCLI and custom seed ISO generation.

---

## Features

- Three-phase deployment workflow: Template Clone, Guest Preparation, Cloud-init Personalization
- Parameter-driven, YAML-based configuration for per-VM customization
- Robust cloud-init integration (hostname, users, SSH keys, network, /etc/hosts and more)
- Compatible with RHEL9, designed for vSphere 7/8 and Windows Server 2019+ admin hosts

---

## Quick Start

### 1. Preparation

- **On the Template VM (RHEL9)**
  - Install `cloud-init`, `cloud-utils-growpart`:
    ```sh
    sudo dnf install cloud-init cloud-utils-growpart
    ```
    💡 The packages are also listed in `infra/req-pkg-cloudinit.txt`.
  - Place the following file to prevent accidental cloud-init runs:
    ```sh
    sudo cp infra/99-template-maint.conf /etc/cloud/cloud.cfg.d/99-template-maint.conf
    ```
  - Power off the template and remove/clean any cloud-init artifacts as needed.

- **On the Windows Admin Host**
  - Install [PowerCLI](https://developer.vmware.com/powercli) and [powershell-yaml](https://github.com/cloudbase/powershell-yaml) module.
  - Place `mkisofs.exe` (from cdrtfe) as specified in the script's `$mkisofs` path.
  - Clone or download this repository and update your parameter files as needed.

### 2. Parameter File Preparation

- Copy `params/vm-settings.example.yaml` and edit it for each VM to deploy:
  - Set vCenter connection, VM hardware, networking, users, and cloud-init parameters.
- Copy all the `templates/original/*_template.yaml` files to `templates/`, and modify if necessary.
- **Advanced:** Customize `scripts/init-vm-cloudinit.sh` if your environment requiures.

### 3. Run Deployment Script

- Open PowerShell in the repository directory.
- Run:
    ```powershell
    .\cloudinit-linux-vm-deploy.ps1 -Phase 1,2,3 -Config .\params\vm-settings.yaml
    ```
    Alternatively you can run each phase separately by specifying `-Phase 1` ⇝ `-Phase 2` ⇝ `-Phase 3`.  
  The script will:
  1. Clone the template VM with specified resources and network.
  2. Prepare the guest (clean cloud-init, remove template marker, set cloud-init config).
  3. Generate cloud-init seed ISO, boot the clone with it, to personalize the VM in accordance with your settings.

### 4. Confirm and Finalize

- Once complete, the deployed VM should boot, apply all cloud-init configuration, and be ready for use.
- Check logs in the `spool/<VMNAME>/` directory if needed.

---

## Directory Structure

```
/
├── cloudinit-linux-vm-deploy.ps1
├── params/
│   └── vm-settings.example.yaml
├── templates/
│   ├── <your copy of '*_template.yaml's>
│   │   ...
│   └── original/
│       ├── user-data_template.yaml
│       ├── meta-data_template.yaml
│       └── network-config_template.yaml
├── scripts/
│   └── init-vm-cloudinit.sh
├── infra/
│   ├── 99-template-maint.conf
│   ├── enable-cloudinit-service.sh
│   ├── req-pkg-cloudinit.txt
│   └── req-pkg-cloudinit-full.txt
└── spool/
    └── <VMNAME>/
```

---

## Notes & Recommendations

- **/etc/hosts Customization**:  
  The kit uses `write_files` in user-data to fully control `/etc/hosts` for each VM.
- **Template Maintenance**:  
  The template VM is protected from cloud-init runs. Clones will automatically remove the protection and enable cloud-init at first boot.
- **PowerCLI** and **powershell-yaml** modules are required on the admin host.
- **mkisofs.exe** must be available as specified in the script.
- For multi-NIC or advanced scenarios, edit the parameter YAML and templates as needed.

---

## References

- [cloud-init documentation](https://cloud-init.io/)
- [VMware PowerCLI](https://developer.vmware.com/powercli)
- [powershell-yaml](https://github.com/cloudbase/powershell-yaml)

---

## License

This project is licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.
