# Cloud-init Ready: Linux VM Deployment Kit on vSphere

## Overview

This kit enables quick deployment of Linux VM from prepared VM Template on vSphere virtual machine infrastructure, using cloud-init framework. The main control program is a PowerShell script: `cloudinit-linux-vm-deploy.ps1`. The workflow is split into four phases:

- **Phase 1:** Create a clone from a VM Template
- **Phase 2:** Prepare the clone to accept cloud-init
- **Phase 3:** Generate a set of cloud-init seed (user-data, meta-data, optional network-config), pack them in an ISO, upload it to a datastore and attach it to the clone's CD drive, then boot the VM and wait for cloud-init to complete
- **Phase 4:** Detach and remove the seed ISO from the datastore, then place /etc/cloud/cloud-init.disabled on the guest to prevent future automatic personalization (can be selectively omitted)

---

Table of contents
- Overview
- Key Points — What This Kit Complements in Cloud-init
- Key Files
- Requirements and Pre-setup (admin host and template VM)
- Quick Start
- Phases — What Does Each Step Perform?
- Template Infra: What is Changed and Why
- mkisofs / ISO Creation Notes
- Operational Recommendations
- Troubleshooting (common cases)
- Logs & Debugging
- License

---

## Key Points — What This Kit Complements in Cloud-init

This kit assumes the intended lifecycle; **template** -> **new clone** -> **initialization** -> **personalization**. It is not intended to replace cloud-init but to complement operational gaps commonly found in real-world cloud-init driven vSphere deployments:

- Filesystem expansion beyond root: kit-specific handling to reformat/resync swap devices and expand other filesystems (not just root)
- NetworkManager adjustments for Ethernet connections (for example: enforce IPv6 disabled, ignore-auto-routes/ignore-auto-dns)
- Precisely setup `/etc/hosts` (along with setting cloud-init's `manage_etc_hosts` to `false`)
- Template safety: template-level blocking of cloud-init and an explicit process to re-enable it on the clone
- Admin-host-driven creation / upload / attach of a cloud-init seed ISO and automated completion detection (quick-check + completion polling)
- Logs and generated artifacts are retained under `spool/<new_vm_name>/` on the admin host for auditing and troubleshooting
- Using PowerShell `-Verbose` shows important internal steps in the console to assist debugging

**Important:** This kit is not designed to "retrofit" cloud-init onto already running production VMs that you want to change later (at the time being).

---

## Key Files

- `cloudinit-linux-vm-deploy.ps1` — main PowerShell deployment script (implements phases 1–4)
- `params/vm-settings_example.yaml` — centralized parameter file (example to be copied and edited per-VM)
- `templates/original/*_template.yaml` — cloud-init user-data / meta-data / network-config YAML templates (copy them directly onto `templates/`; edit if required)
- `scripts/init-vm-cloudinit.sh` — script transferred and run on the clone in Phase-2
- `infra/` — template VM preparation tools:
  - `prevent-cloud-init.sh` — installs the files below to manage base setting and prevent template VM from accidental invocation of cloud-init, etc.
    - `cloud.cfg`, `cloud.cfg.d/99-template-maint.cfg`
  - `enable-cloudinit-service.sh` — helper to ensure cloud-init services enabled
  - `req-pkg-cloudinit.txt` (optional `infra/req-pkg-cloudinit-full.txt`) — required rpm package lists
- `spool/` — the script writes per-VM output to spool/<new_vm_name>/ (`dummy.txt` is included merely for this empty folder to exist in GitHub repository)

---

## Requirements / Pre-setup

Admin host (PowerShell environment — Windows 2019+/11 is the primary target):
- Windows PowerShell (5.1+)
- VMware PowerCLI (v13.3+ recommended)
- powershell-yaml module
- mkisofs (Win32 mkisofs from [cdrtfe](https://sourceforge.net/projects/cdrtfe/) is the expected binary by default; see mkisofs notes below)
- Clone this repository or unzip the ziped folder from Assets (hereinafter called *"script_home"*)

Template VM (example: RHEL9):  
  Template is a VM you tailored (this kit won't provide). It may consist of considerable minimal resources, e.g., 2 CPUs, 2.1GB memory, 8GB primary disk, 2GB swap / 500MB kdump disks with 'Thin' vmdk format, all of which can be automatically expanded by the capabilities of this kit during provisioning.

- open-vm-tools
- cloud-init, cloud-utils-growpart (dracut-config-generic is optional if you need dracut operations)
- A CD/DVD drive present on the VM (seed ISO is attached to the CD drive)
- Copy `infra/` to the template VM and run `prevent-cloud-init.sh` as root to prepare cloud-init base setting and protect the template
- One administrative user to assign to `username` in parameter file. This local system user account is necessary for VIX/Guest Operations API such as `Copy-VMGuestFile` / `Invoke-VMScript` comdlets; the user must exist and is allowed to execute at least `/bin/bash` as root via `sudo` (`NOPASSWD` is not necessary).  

**Important:** The partitions that need to be expanded must be the **LAST** partion in the disks, otherwize expantion is theoretically impossible. Script limitations (for now):
- Supported filesystem: `ext2/3/4` and `swap`
- LVM is not supported

Line endings:
- PowerShell scripts and params YAML: CRLF (Windows)
- Guest shell scripts and cloud-init templates: LF (Unix)

---

## Quick Start (short path)

1. Clone this repo or unzip this holder on the Windows admin host, and install PowerCLI / powershell-yaml.
2. On the template VM:
   - copy `infra/` into the template filesystem and run:
     ```sh
     cd infra
     sudo /bin/bash ./prevent-cloud-init.sh
     ```
     This replaces `/etc/cloud/cloud.cfg` with the kit-optimized config, installs `/etc/cloud/cloud.cfg.d/99-template-maint.cfg` and create `/etc/cloud/cloud-init.disabled`.
   - Shutdown the VM and convert to a vSphere VM Template.
3. On the admin host:
   - Copy `params/vm-settings_example.yaml` to customize as your specification with a new filename you prefer (e.g. `params/vm-settings_myvm01.yaml`).  
     **Tip:** Use the deploy target VM name in the file name so that it is in sync with `new_vm_name` parameter to keep things clear.
   - Copy `templates/original/*_template.yaml` files to directly on `templates/`.
4. Open a PowerShell console with *script_home* as current folder and run the deploy script:
   ```powershell
   .\cloudinit-linux-vm-deploy.ps1 -Phase 1,2,3 -Config .\params\vm-settings_myvm01.yaml
   ```
   - You may run single phases (`-Phase 1`) or continuous sequences (`-Phase 1,2,3`). Non-contiguous phase lists like `-Phase 1,3` are not supported and will fail.
   - Automatic power-on/shutdown during a script run can be suppressed with runtime option `-NoRestart`, unless the run includes multiple phases. Even if a single phase, in certain cases where the logic cannot be satisfied without a power-on/shutdown, user will be prompted for confirmation.

   - `spool/<new_vm_name>/` will be created under *script_home* and the generated files and logs are placed there.

   Refer to help contents included in the script itself for more detail; call:
   ```powershell
   Get-help ./cloudinit-linux-vm-deploy.ps1 -detailed
   ```

---

## Phases — What Does Each Step Perform?

Important: Phase selection must be a contiguous ascending list (single phase also allowed). Examples:
- Valid: `-Phase 1` or `-Phase 1,2,3`
- Invalid: `-Phase 1,3` (non-contiguous)

Phase 1–3 form the typical deployment flow. Phase 4 is a post-processing operation with different semantics and is recommended to be run after confirming Phase-3 succeeded.

### Phase 1 — Automatic Cloning
Purpose:
- Create a new VM by cloning the VM Template and apply specified vSphere-level hardware modification (CPU, memory, disk sizes). This phase does not perform guest power-on or shutdown.

High-level steps:
1. Validate no VM name collision
2. Resolve resource pool / datastore / host / portgroup from params
3. New-VM clone operation
4. Apply CPU / memory sizings
5. Resize vmdk entries (switching of virtual disk format (Thick/Thin etc.) on cloning can also be specified in parameters)

Result:
- A new VM object appears in vCenter (left powered off).

Cautions / Notes:
- Don't run if a VM with the same name already exists on the vCenter (the script checks and aborts).

### Phase 2 — Guest Initialization
Purpose:
- Perform guest-side initialization to remove template protections and get ready for cloud-init. After this phase completes the VM is left powered on.

High-level steps:
1. Power on the VM (this power-on is necessary for the purpose of this phase; if `-NoRestart` switch is detected, operator will be prompted whether to abort the run or temporarily allow this power operation)
2. Transfer `scripts/init-vm-cloudinit.sh` into the guest and run it; this script does the following tasks:
   - subscription-manager cleanup (RHEL specific)
   - Remove existing NetworkManager Ethernet connection profiles (Ethernet only)
   - Run `cloud-init clean`
   - Truncate `/etc/machine-id`
   - Remove `/etc/cloud/cloud-init.disabled` (re-enable cloud-init)
   - Remove `/etc/cloud/cloud.cfg.d/99-template-maint.cfg`
   - Create `/etc/cloud/cloud.cfg.d/99-override.cfg` to set `preserve_hostname: false` and `manage_etc_hosts: false`

Result:
- Clone is ready for cloud-init personalization, ends with powered on state.

Cautions / Notes:
- Ensure the credential (`username` and `password`) in the parameter file is correct for the existing administrative user on the VM — the script uses `Invoke-VMScript` and `Copy-VMGuestFile` with the credentials. This user must be able to run `sudo /bin/bash` (refer to [Requirements / Pre-setup](#Requirements---Pre-setup)).
- The kit expects to remove template-level blocking files; ensure the init script `scripts/init-vm-cloudinit.sh` is appropriate for your distribution.
- As the VM is left powered on, administrators can log in to verify or perform adjustments if needed. When you are finished, you may shut it down manually, otherwise it will be shut down automatically at the beginning of Phase-3.
- Restarting at this state is strongly discouraged because next boot will trigger cloud-init personalization regardless of appropriate seed ISO attachment; it will make the clone inconsistent and your will have to resort to removing the VM to start things over from Phase-1.

### Phase 3 — Cloud-init seed creation & personalization
Purpose:
- Boot the VM with the seed ISO attached and wait for cloud-init to finish applying the personalization. In the preparation stage, script renders `user-data` / `meta-data` / `network-config` from template YAMLs + parameters, then create an ISO, attach it to the VM's CD drive, boot the VM and wait for cloud-init to complete. The phase ends with powered-on state.

High-level steps:
1. Shutdown the VM if it is powered on (and if `-NoRestart` is not specified)
2. Render `user-data`/`meta-data`/`network-config` from seed templates + parameter. Especially for user-data, the kit will dynamically build a `runcmd` block for:
   - `resize2fs` for filesystems other than root partition (root partition is resized by cloud-init default)
   - Swap reformat to expand size; taking care of UUID consistency in `fstab` entry
   - NetworkManager `nmcli` modifications for Ethernet interface profiles; accompanied with setting ignore-auto-routes/ignore-auto-dns and ipv6 disablement
3. Generate an ISO with mkisofs and upload it to datastore (path defined in parameter file) to attach to the clone's CD/DVD drive
4. Power on the VM and watch until cloud-init processes finish by transfering checking shell scripts onto the VM and run periodically until defined timeout (the check scritps are normally purged after use)

Result:
- cloud-init has applied the personalization and the VM is ready. VM is left powered on in the end.

Cautions / Notes:
- If `/etc/cloud/cloud-init.disabled` remains on the guest, this phase is meaningless — the script checks early and aborts if found.
- `/etc/hosts` is written from scratch with recommended self records. If any additional static host records are required, edit `templates/user-data_template.yaml` beforehand to add records in `write_files > content`. 
- Script will cancel ISO upload and error exit if the target datastore path already contains an ISO with the same name. The script is designed not to overwrite an existing ISO. Typical resolution:
  - Run Phase-4 alone (typically with `-NoCloudReset` since creation of `/etc/cloud/cloud-init.disabled` is not suitable for this occation), which is far quick and convenient than manual detach → removal on vSphere Client (do not foreget to answer to "Sure to detach?" prompt from vSphere if clone is powered on).
- Re-running Phase-3 repeatedly (without running Phase-4) can lead to repeated SSH host key regeneration and duplicated NetworkManager connection profiles — be mindful and use Phase-4 to finalize once satisfied.
- When `-NoRestart` option is given, both shutdown and power-on in this phase are skipped. That is *allowed* operation for Phase-3, but mind it is edge case, viable for development/testing purpose only; because a shutdown is required to boot with attached seed ISO, in these cases the script will warn you at the end of Phase-3 thnat manual boot/reboot is required. ISO create and attach will be pursued normally.

### Phase 4 — Cleanup and finalization
Purpose:
- Detach the seed ISO from the VM, remove the ISO from the datastore, and create `/etc/cloud/cloud-init.disabled` on the guest to prevent cloud-init activation on later boots. If `-NoCloudReset` is supplied, `cloud-init.disabled` creation is skipped.
- Phase-4 can also be used alone to ensure seed ISO is detached from VM's CD/DVD drive and the ISO is removed from datastore, e.g., to allow a subsequent Phase-3 rerun — use with `-NoCloudReset` is spot-on for this purpose.

High-level steps:
1. Detach CD/DVD media from the VM
2. Remove the uploaded ISO from the datastore
3. Create `/etc/cloud/cloud-init.disabled` to block future activation of clout-init. (unless `-NoCloudReset` is specified)

Result:
- The seed ISO is detached and removed, and cloud-init is disabled permanently on the guest to prevent further cloud-init personalization effect.

Cautions / Notes:
- Phase-4 doesn't try to power-on the VM even if it is shutdown. If the VM is powered off or VMware Tools is not ready, script aborts with error just before `cloud-init.disabled` creation after ISO attach.
- If you execute Phase-4 while the VM is running, vSphere blocks the script process until you answer "Yes" to the prompt (on VMRC or the VM page of vSphere Client) whether you are sure you want to detach it.

---

## Template Infra: What is Changed and Why

`cloud.cfg` and `99-template-maint.cfg` in `infra/` folder have been tuned to make the source Template safe to operate and maintain cloud-init environment for cloning:

The included `cloud.cfg` is based on distro package default for RHEL9 (original is saved in `default/` for reference). The parameters customized for this kit is marked with "[CHANGED]". Those marked with "[NOTE]" are kept default and important for kit's intended behavoir. "[CHANGED]" parameters are as follows (may change without notice):

- users: [] — suppress creation of default user `cloud-user`
- disable_root: false — allow root SSH login; 'true' creates `/etc/ssh/sshd_confg.d/50-cloud-init.conf` only for this purpose
- preserve_hostname: true — protect `/etc/hostname` on template from automatic update (on clones we create `99-override.cfg` to override with `false`)
- Most cloud-init modules are set to `once-per-instance` or `once` so that the template and clones do not execute modules repeatedly or unexpectedly
- Package update/upgrade cloud-init module was removed from cloud-final to avoid accidental package changes during cloning

Notes:
- SSH host key regeneration settings (i.e., `ssh_deletekeys`, `ssh_genkeytypes`) are left default: it could be programmed via `runcmd` but this default is considered optimal.

---

## mkisofs & ISO Creation Notes

- The kit assumes a Windows admin host and by default the script variable `$mkisofs` points to a Win32 `mkisofs.exe` binary bundled with cdrtfe (https://sourceforge.net/projects/cdrtfe/). Adjust `$mkisofs` in the script's global variables if you use a different binary or a Linux environment on Windows (e.g., `genisoimage` under WSL).
- The ISO must be created with the volume label `cidata` and include `user-data`, `meta-data`, `network-config` files in the root as cloud-init specification demands.
- Depending on the ISO creator implementation, you may need to adapt the `$mkArgs` commandline options used in the script (for encoding, Joliet/RockRidge flags, etc.). If mkisofs fails, confirm `$mkisofs` path and `$mkArgs` match your executable.

---

## Operational Recommendations

- Phase selection:
  - You may run any contiguous sequence of phases or a single phase. Non-contiguous selection (e.g., `-Phase 1,3`) will be rejected.
  - Prefer running Phase-4 as a separate step after you have confirmed Phase-3 succeeded (Phase-4 is a finalization step).
- VMware Tools:
  - Required for Phase 2/3/4 guest file operations. Verify `open-vm-tools` is installed and functioning on the guest.
- Credentials:
  - `params/*.yaml` contains credentials in plain form in the example. Treat those files as sensitive. Use `VICredentialStore` or secure methods to protect secrets in production.
- spool directory:
  - The kit includes `spool/` folder with a dummy file so that it can exist on the GitHub repository. If you noticed the folder absent, please create it prior to script execution.

---

## Troubleshooting (common cases)

- cloud-init did not run
  - Check the clone does not still have `/etc/cloud/cloud-init.disabled` (Phase-2 must have removed it). Verify `scripts/init-vm-cloudinit.sh` returned success.
  - Inspect `spool/<new_vm_name>/cloudinit-seed/` to confirm generated `user-data`, `meta-data`, `network-config` content and timestamps. Check `spool/cloudinit-linux-seed.iso` too.
  - Verify VMware Tools are running; if not, `Copy-VMGuestFile` and `Invoke-VMScript` will fail.
  - Check guest logs: `/var/log/cloud-init.log`, `/var/log/cloud-init-output.log`, and `/var/lib/cloud/instance/*`.

- ISO creation / upload failure
  - `$mkisofs` not found or wrong binary. Confirm `$mkisofs` path in the script or use a compatible ISO creator and update the script.
  - `seed_iso_copy_store` is malformed. Expected form: `[DATASTORE] path/` (e.g., `[COMMSTORE01] cloudinit-iso/` —trailing '/' is optional).
  - Datastore path already contains an ISO file with that name (common when rerun Phase-3). Solution: run Phase-4 alone with `-NoCloudReset` option to remove the existing ISO (see also "Cautions / Notes" in [Phase-3 details](#Phase-3---Cloud-init-seed-creation---personalization) section)

- Network configuration not applied as expected
  - Ensure `templates/network-config_template.yaml` has `{{netif*.netdev}}` placeholders that match `netif*:` properies in the parameter file. Also check if `netif*.netdev` values in params match the guest's actual interface device names (e.g., `ens192`). Additionally verify the mapping of vSphere NIC order (Network \<index\>) vs. guest device naming if your environment renumbers devices.

---

## Logs & Debugging

- Detailed logs and generated files are stored under `spool/<new_vm_name>/` on the admin host, where the primary log file is `deploy-YYYYMMDD.log`. The script writes additional files such as the generated seed ISO and the sources of it in `cloudinit-seed/` subfolder, which is removed and re-created at each Phase-3 run. Some other temporary files are also created there but removed after a run.
- Run the main script with `-Verbose` to see more internal steps printed on the console for debugging.

---

## License

This project is licensed under the MIT License - see the repository LICENSE file for details.
