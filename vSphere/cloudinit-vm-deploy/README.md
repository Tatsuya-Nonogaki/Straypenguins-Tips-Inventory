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
    cd infra/
    sudo install -m 644 /dev/null /etc/cloud/cloud-init.disabled
    sudo install -m 644 ./cloud.cfg /etc/cloud    # Overwrite
    sudo install -m 644 ./99-template-maint.cfg /etc/cloud/cloud.cfg.d
    ```
    💡 The attached shell script `infra/prevent-cloud-init.sh` will do the jobs for you. Bring the whole directory into the template VM and execute it with root privileges.
  - Remove/clean any cloud-init artifacts as needed. Power off the VM and turn it into a Template.

- **On the Windows Admin Host**
  - Install [PowerCLI](https://developer.vmware.com/powercli) and [powershell-yaml](https://github.com/cloudbase/powershell-yaml) module.
  - Place `mkisofs.exe` (from cdrtfe) as specified in the script's `$mkisofs` path.
  - Clone or download this repository and update your parameter files as needed.

### 2. Parameter File Preparation

- Copy `params/vm-settings_example.yaml` and edit it for each VM to deploy:
  - Set vCenter connection, VM hardware, networking, users, and cloud-init parameters.
- Copy all the `templates/original/*_template.yaml` files to `templates/`, and modify if necessary. In certain cases, you may also need to edit `/etc/cloud/cloud.cfg` so that it aligns with the new parameters.
- **Advanced:** Customize `scripts/init-vm-cloudinit.sh` if your environments requiure.

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
- Check logs in the `spool/<VMNAME>/` directory and `/var/log/cloud-init*.log` files if needed.

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
│   │   ...
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

- **/etc/hosts Customization**:  
  The kit uses `write_files` in user-data to fully control `/etc/hosts` for each VM.
- **Template Maintenance**:  
  The template VM is protected from cloud-init runs. Clones will automatically remove the protection and enable cloud-init at first boot.
- **PowerCLI** and **powershell-yaml** modules are required on the admin host.
- **mkisofs.exe** must be available as specified in the script.
- For multi-NIC or advanced scenarios, edit `cloud.cfg` and templates as needed.

---

## References

- [cloud-init documentation](https://cloud-init.io/)
- [VMware PowerCLI](https://developer.vmware.com/powercli)
- [powershell-yaml](https://github.com/cloudbase/powershell-yaml)
- [cdrtfe (includes mkisofs win32)](https://sourceforge.net/projects/cdrtfe/)

---

## License

This project is licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.
