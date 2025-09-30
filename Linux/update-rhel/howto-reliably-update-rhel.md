# How to Reliably Update RHEL Server

This document describes a safe and reliable procedure for updating a RHEL system within the same major version.

---

## 🔧 Phase 1: Preparation and Update

1. **Determine the Target Release**  
   Decide on your target RHEL release number (e.g., 9.6). See [RHEL Downloads](https://access.redhat.com/downloads/content/479/ver=/rhel---10/10.0/x86_64/product-software) and look up the appropriate kernel version in, for example, [Packages—v9](https://access.redhat.com/downloads/content/479/ver=/rhel---9/9.6/x86_64/packages).

2. **Select and Prepare the Kernel Update Script**  
   Choose the correct script (see also [Script Table below](#script-selection-table)):
   - `update-kernel.sh`: For systems **without** kernel-devel, updating **within** the same release (e.g., 9.5→9.5)
   - `update-kernel-withdevel.sh`: For systems **with** kernel-devel, updating **within** the same release
   - `update-kernel-withrel.sh`: For systems **without** kernel-devel, updating **across** different releases (e.g., 9.5→9.6)
   - `update-kernel-withdevel-withrel.sh`: For systems **with** kernel-devel, updating **across** releases

   Edit the `releasever=` variable (only present in scripts without `-withrel`) and the `newkernelver=` variable at the top of the script as appropriate.

3. **Pre-Check: List Current Kernel-Related Packages**  
   Run the update script with the `-l` option to list current kernel-related packages. For example:
   ```bash
   ./update-kernel-withdevel-withrel.sh -l
   ```

4. **Clean DNF Cache**  
   ```bash
   dnf clean all
   rm -rf /var/cache/dnf
   ```

5. **Recreate DNF Cache (Ignore Excludes)**  
   This ensures all metadata is refreshed:
   ```bash
   dnf --disableexcludes=main makecache
   ```

6. **Change Directory to Script Location**  
   For example:
   ```bash
   cd /work/rhel9
   ```

7. **Update Kernel-Related Packages**  
   Run the script to update only kernel-related packages:
   ```bash
   ./update-kernel-withdevel-withrel.sh
   ```

8. **Update Other Packages**  
   ```bash
   dnf update
   ```
   If any `*.rpmsave` or `*.rpmnew` files are created during update, review and merge changes as needed. To find these files:
   ```bash
   find / -regex '.*/.*\.rpm\(save\|new\)'
   ```

9. **Reboot the System**  
   ```bash
   systemctl reboot
   ```
   Or use your preferred method.

---

## 🔧 Phase 2: Post-Update Checks

10. **Post-Check: Confirm Active Kernel and OS Version**  
    After reboot, verify the running kernel and OS version:
    ```bash
    uname -a
    cat /etc/os-release
    # or
    cat /etc/redhat-release
    ```

11. **Post-Check: List Installed Kernel-Related Packages**  
    Use the update script with the `-l` option again to confirm package versions:
    ```bash
    ./update-kernel-withdevel-withrel.sh -l
    ```

12. **Retry Update if Necessary**  
    There is a slight chance the updated kernel requires additional package updates. Run:
    ```bash
    dnf update
    ```

13. **Check for Broken Dependencies**  
    ```bash
    dnf repoquery --unsatisfied
    ```

14. **Final Review of .rpmsave/.rpmnew Files**  
    Check again for any new config files that may have been created and merge as appropriate.

---

## Script Selection Table

👉 **Browse these files on [GitHub Web](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory/tree/main/Linux/update-rhel)**

| Use Case                          | Script Name                         |
|------------------------------------|-------------------------------------|
| No kernel-devel, same release      | `update-kernel.sh`                    |
| With kernel-devel, same release    | `update-kernel-withdevel.sh`          |
| No kernel-devel, across releases   | `update-kernel-withrel.sh`            |
| With kernel-devel, across releases | `update-kernel-withdevel-withrel.sh`  |

---

This procedure leverages the `-l` (list-only) script option for before/after verification of kernel package versions, and provides all commands for a consistent, reliable RHEL minor release update.
