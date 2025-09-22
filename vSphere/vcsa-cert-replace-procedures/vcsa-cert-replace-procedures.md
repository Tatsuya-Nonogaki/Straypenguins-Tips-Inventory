# vCSA Certificate Replacement and Renewal Procedures

## 🧭 Overall policy

- Select between `vCert` and `fixcerts.py` based on your operational needs, certificate types, and available features. Both tools are robust and reliable; in many scenarios, using them in combination increases flexibility and success rate.
  > **Resilience advantage:** If one tool encounters a limitation or fails to address a specific certificate type, you can seamlessly switch to the other. This "failover between tools" is a deliberate part of these procedures—ensuring certificate renewal remains possible no matter the situation.

  > 📝 **Note:** An invaluable feature of `fixcerts.py` is its ability to specify an extended validity period for renewed certificates (`--validityDays <DAYS>`).  
  > However, the actual validity of generated certificates **cannot exceed the expiry of the vCSA root CA**—even if a longer value is specified, certificates will expire at the root CA's end date.

  > 📝 **Note:** Some certificate types (notably STS certificates) are not fully covered by either tool. It is recommended to have `vCert` available—even if your main tool is `fixcerts.py`! For example, STS certificates are not visible via VECS CLI or `fixcerts.py`, and require `vCert` or equivalent tools for inspection and renewal.

- Enable logging of the terminal application as far as possible  
  It is strongly recommended to run the commands, including the execution of the `vCert.py`/`fixcerts.py` on a `SSH` session with a terminal software, e.g., `PuTTY` or OS standard `ssh`.

### Pre-Renewal Checklist
- **Always take a cold VM snapshot of the targetted vCSA, once shutting it down, before making any changes.**
- Before modifying anything, capture the current status of all certificates. First, use this shell one-liner to get all VECS-managed certificates:
    ```
    for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list | grep -v TRUSTED_ROOT_CRLS); do echo "[*] Store :" $store; /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text | grep -ie "Alias" -ie "Not Before" -ie "Not After"; done
    ```
    > You can find this as a separate script file, `list-vecs-certs.sh`, for ease of use.

- Next, obtain information about the STS certificates and Extension Thumbprints, which are **not covered by the above command**, using `vCert.py`:
    ```
    ./vCert.py --run config/view_cert/op_view_11-sts.yaml
    ./vCert.py --run config/check_cert/op_check_10-vc_ext_thumbprints.yaml
    ```
    > 📝 **Note:** Because the STS certificates and Extension Thumbprints are not visible via VECS CLI or `fixcerts.py`, it is necessary to have `vCert.py` available—even if your main tool is `fixcerts.py`! The second check is included in "1. Check current certificate status" main menu or an invocation with "--run config/op_check_cert.yaml" option.

- Check the health of the vCenter Server  
  - Service status (can be checked on VAMI graphically)
     ```
     service-control --status --all
     ```
  - Check for prior errors (optional, for extra caution) in:
    - **`/var/log/vmware/vmcad/`**

      Mainly:
      - certificate-manager.log  _#Manual certificate operations_
      - vmcad.log                _#VMCA service and certificate lifecycle events_
      - vmca-audit.log           _#Audit trail of certificate changes_

      Optionally:
      - vmcad-syslog.log         _#system-level VMCA events_

    - **`/var/log/vmware/sso/`**

       Mainly:
       - sts-health-status.log    _#STS health and certificate issues_
       - ssoAdminServer.log       _#SSO server operations and errors_
       - vmware-identity-sts.log  _#Secure Token Service (STS) and identity events_

       Optionally:
       - tokenservice.log         _#Token service operations_
       - sso-config.log           _#SSO configuration changes/events_
       - openidconnect.log        _#OpenID Connect related authentication events_

  - Check for storage utilization:
    **Check the disk partitions not reaching full, especially `/storage/log`**
    ```
    df -h
    ```
    or
    ```
    df -h /storage/log
    ```
    > ⚠️ **Warning:**  
    > If the `/var/log/vmware` directory (or its backing `/storage/log` partition) is nearly full or out of space, certificate management operations may fail or cause vCSA services to become unavailable or unstable.  
    > Ensure there is sufficient free space **before** proceeding.  
    > If space is low, consult [vCenter log disk exhaustion or /storage/log full](https://knowledge.broadcom.com/external/article/313077/vcenter-log-disk-exhaustion-or-storagelo.html) for diagnostic and cleanup guidance before attempting any certificate changes.

### Post-Renewal Checklist
After completing certificate renewal procedures, it is essential to verify the health and status of the vCenter Server and its certificates.
- Re-run the certificate status one-liner, and STS certificates and Extension Thumbprints checks with `vCert.py` to confirm that all renewed certificates have the correct expiry dates and consistency.
- Check the service health using
  ```
  service-control --status --all
  ```
- Review the relevant logs in `/var/log/vmware/vmcad/` and `/var/log/vmware/sso/` for any errors or warnings.
- Inspect the vCenter UI for certificate-related alerts to ensure that all services are operating normally and securely.
- If you have external systems such as backup, monitoring, or automation software (e.g., Veeam Backup & Replication) that connect to vCenter Server, you may need to re-establish trust by updating or re-configuring the integration to re-import the new vCenter certificates. This is especially necessary when Machine SSL or CA certificates have been renewed or replaced.

---

## 🛠️ Procedures for vCert
`vCert.py` is primarily designed for use via its interactive menu. While it does support direct operations with the `--run` option by specifying the path to a particular YAML file, this usually requires more typing, and the other command-line options are quite limited.

However, depending on the situation, using the `--run` option for specific operations can be beneficial. For your convenience, the table **vCert.py direct operation arguments** in the separate file `vcsa-cert-list-chart.md` summarizes the available YAML file paths for each operation category.

### Procedures
1. **Run vCert.py:**  
   Start by just `./vCert.py`. If you pass `--user <user@vphere> --password <pswd>`, authentication prior to each authoritative operation is omitted.

2. **Check current certificate status:**  
   In the main menu, select "1. Check current certificate status" and proceed.

3. **Try full-auto renewal first:**  
   Choose "6. Reset all certificates with VMCA-signed certificates" in the main menu and proceed.

4. **Service restart prompt:**  
   Answer "N" (default) to "Restart VMware services [N]: " prompt, if succeeded or failed.

5. **Check logs for errors after vCert.py runs (optional, for extra caution):**  
   - Review `/var/log/vmware/vmcad/` and `/var/log/vmware/vmware/sso/` for signs of certificate renewal problems.
   - Check the own log files of vCert.py. Official Web document say (extract);  
     > The script will create `/var/log/vmware/vCert/vCert.log` (which will be included in a support bundle), and a directory in `/root/vCert-master` with the name format 'YYYYMMDD', which will include several sub-directories for staging, backups, etc. Other than certificate backup files, the temporary files are deleted when the vCert tool exits.

6. **Post-renewal verification and service restart:**  
   - If the recreation of certificates was successful, choose "8. Restart services" in the main menu. (This will take some time.)
   - After services restart, re-run the certificate status one-liner above to confirm expiry dates are updated.
   - Also check for any vCenter alerts or certificate-related warnings in the UI.

7. **If the recreation failed, fully or partially:**  
   1. Select "1. Check current certificate status" in the main menu to check which certificates failed.
   2. Also, check with the one-liner command:
      ```
      for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list | grep -v TRUSTED_ROOT_CRLS); do echo "[*] Store :" $store; /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text | grep -ie "Alias" -ie "Not Before" -ie "Not After"; done
      ```
   3. Try recreating certificates per Certificate-Type, by selecting "3. Manage certificates" in the main menu and proceeding to the specific sub menu such as "2. Solution User certificates". Check the status of the certificates again.
      > *Refer to the chart **vCert.py Operation for each certificate** in the separate file `vcsa-cert-list-chart.md` for correct menu entries.*
   4. If any of the certificates were updated, check for consistency in Extension Thumbprints by selecting "3. Manage certificates" in the main menu then "6. vCenter Extension thumbprints" (or directly run `./vCert.py --run config/manage_cert/op_manage-vc-ext-thumbprints.yaml`). If any MISMATCH are found, proceed with "Y" to solve.
   5. After complete renewal of all the failed certificates, go back to the main menu and select "8. Restart services". (This will take some time.)

8. **Final health check:**  
   Verify the vCSA service health and certificate validity. For detailed verification steps, refer to the "Post-Renewal Checklist" section under "Overall policy" at the beginning of this document.

---

💡 **Tips:**
- **Always snapshot before any changes!**  
- **After renewal, verify expiry dates using the shell one-liner and check for vCenter alerts.**
- **Check logs after each major operation for hidden errors.**

---

## 🛠️ Procedures for fixcerts.py
`fixcerts.py` has occasionally been reported to have stability issues, where renewal may succeed for some certificate types but not others. However, in practice, it has proven to be reliable in many cases. To further reduce the possibility of renewal failures, it is recommended to perform **staged renewals by certificate type** rather than renewing all at once. Always use the latest version (`fixcerts_3_2.py` at the time of writing).

### Procedures
1. **Run fixcerts.py per certificate-type:**  
   - Execute the script for each certificate-type individually, using appropriate command-line options. For example:
     ```
     ./fixcerts.py replace --certType machinessl --validityDays 3650 --serviceRestart False
     ```
     **Key Points:**  
     - Change the `--certType` argument for each run to match the certificate-type.  
       *Refer to the chart **fixcerts.py Operation for each certificate** in the separate file `vcsa-cert-list-chart.md` for correct values (e.g. `machinessl`, `solutionusers`, etc.).*
     - Use the `--validityDays` option to extend certificate validity, if desired.  
       **Note:** The actual period of generated certificates **cannot exceed the expiry of the root CA**—even if a longer value is specified, the certificates will expire at the root CA's end date.
     - Always set `--serviceRestart False` for each run. You will restart services after all renewals are complete.
     - Consider passing the `--debug` option to increase verbosity and aid troubleshooting.
     - Consider running the script in an SSH session with logging enabled to capture all console output.
     - **Note:** `fixcerts.py` does not provide an interactive menu; all operations are done via command-line arguments.

2. **Verify certificate renewal after each type:**  
   - After each certificate-type renewal, run the certificate status one-liner (or the dedicated script file) to confirm expiry dates have changed:
     ```
     for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list | grep -v TRUSTED_ROOT_CRLS); do echo "[*] Store :" $store; /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text | grep -ie "Alias" -ie "Not Before" -ie "Not After"; done
     ```
   - Especially after renewal of STS or lookupservice related certificates, check by running;
     ```
     ./vCert.py --run config/view_cert/op_view_11-sts.yaml
     ```
   - Review for any certificates that were not updated.

3. **Check logs for errors after each run (optional, for extra caution):**  
   - Check standard system logs for issues:
     - `/var/log/vmware/vmcad/`
     - `/var/log/vmware/vmware/sso/`
   - Check `fixcerts.py`'s own log file:  
     - `fixcerts.log` (found in the current working directory where the script was executed).

4. **Troubleshoot and retry failed renewals:**  
   - If any certificate-type fails to renew, attempt rerunning `fixcerts.py` for that type.
   - Use the `--debug` option for more detailed error output.
   - If failures persist, consider manual renewal using `vecs-cli` or consult official product support documentation.
   - If any of the certificates were updated, check for consistency in Extension Thumbprints by running;
     ```
     ./vCert.py --run config/manage_cert/op_manage-vc-ext-thumbprints.yaml
     ```
     If any MISMATCH are found, proceed with "Y" to solve.
5. **Restart services after all renewals:**  
   - Once all certificate-types have been renewed successfully, restart vCSA services to apply changes by running:
     ```
     service-control --stop --all && service-control --start --all
     ```
     > This is the recommended and safe method to restart services, as used internally by `fixcerts.py` itself.

6. **Final health check and post-renewal verification:**  
   Verify the vCSA service health and certificate validity. For detailed verification steps, refer to the "Post-Renewal Checklist" section under "Overall policy" at the beginning of this document.

---

💡 **Tips:**
- **Always snapshot before any changes!**
- **After renewal, verify expiry dates using the shell one-liner and check for vCenter alerts.**
- **Check logs, including `fixcerts.log`, after each major operation for hidden errors.**
- **Use the `--debug` option for more detailed troubleshooting if issues arise.**

---
