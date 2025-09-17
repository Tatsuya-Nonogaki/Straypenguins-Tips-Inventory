# SELinux Policy Troubleshooting: Resolving Audit Denials for a Custom Service

## Overview

This document records the investigation, diagnostics, and resolution steps for SELinux policy denials encountered by a custom service/domain (e.g., `mysvcd_t`). The process covers how to identify, analyze, and resolve permission issues when running services under SELinux in Enforcing mode.  
The workflow and troubleshooting checklist can be adapted for many SELinux modules (e.g., httpd custom policies) by substituting the relevant domain/type and permissions.

**Related Documents**
- [Manage SELinux to Allow httpd to Access Port 7003/TCP](selinux-mod_wl-allow-httpd-7003.md)
- [Create SELinux Policy Module for Your Own Service](selinux-create-own-service-policy.md)

---

### Glossary

- **Domain/type:** SELinux security label assigned to a process (e.g., `mysvcd_t`)
- **Class:** SELinux object class (e.g., `tcp_socket`, `file`)
- **Permission/operation:** Specific allowed actions for a class (e.g., `connect`, `getopt`)
- **Policy module:** Packaged SELinux policy rules for installation (`.pp` *(Policy Package)* file; its source is usually `.te` *(Type Enforcement)*, plus others like `.if`, `.fc`, etc.)

---

## Environment &amp; Example Situation

- **Service:** `/opt/mysvc/bin/mysvcd`
- **SELinux domain:** `mysvcd_t`
- **SELinux status:** Enforcing
- **Symptoms:** Repeated audit denials for operation `getopt` on class `tcp_socket` during outbound connection attempts to `x.x.x.x:443`.

---

## Procedure Outline

- [Diagnostics Steps](#diagnostics-steps)
  - [1. Identify Denied Operations](#1-identify-denied-operations)
  - [2. Verify Running Context](#2-verify-running-context)
  - [3. Check Policy Permissions](#3-check-policy-permissions)
- [Resolution Steps](#resolution-steps)
  - [1. Update Policy Source](#1-update-policy-source)
  - [2. Rebuild and Reload Policy](#2-rebuild-and-reload-policy)
  - [3. Verify Policy is Active](#3-verify-policy-is-active)
  - [4. Test Service Behavior](#4-test-service-behavior)
  - [5. If Not Solved or Another Denial is Observed](#5-if-not-solved-or-another-denial-is-observed)
- [Key Lessons](#key-lessons)
- [References](#references)

---

## Diagnostics Steps

### 1. Identify Denied Operations

Check audit logs for SELinux denials using `ausearch`.

```bash
ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR -su mysvcd_t
```

Use `ausearch` to efficiently locate relevant information. Below is a quick reference:

| Goal                           | Command Example                                                  | Description              |
|---------------------------------|------------------------------------------------------------------|--------------------------|
| All SELinux denials            | `ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR`          | Message type, case-sensitive     |
| By process name                | `ausearch -c mysvcd`                                             | Full executable name only        |
| By subject domain/type         | `ausearch -su mysvcd_t`                                          | Partial match on scontext        |
| By message type                | `ausearch -m AVC`                                                | AVC: most common denials         |
| By start time (since)          | `ausearch -ts today`<br>`... -ts mm/dd/yy 'HH:MM:SS'`<br>`... -ts recent`(means 10 min ago)  | Filter by time   |
| Fuzzy match (with grep)        | `ausearch ... \| grep mysvcd`                                    | Any line with string             |
| Command prefix match (with grep)| `ausearch ... \| grep 'comm="mysvcd'`                           | Commands starting with name      |

📝 **Note:**
- In the output, look for `denied { ... }` and `tclass=...` to help identify the cause and resolution.
- `-c`/`--comm`: Command name, i.e. executable filename (not policy name).
- `-su`: scontext (SELinux subject context) e.g., `system_u:system_r:mysvcd_t:s0`, practically a domain/type.
- Combine options for precise results (e.g. by process and time).
- While `AVC` is most common for denials, `USER_AVC`, `SELINUX_ERR`, and `USER_SELINUX_ERR` can surface in special cases (user-space denials, errors in SELinux processing).
- See [audit(8) man page](https://man7.org/linux/man-pages/man8/ausearch.8.html) for advanced usage.

Typical denial entry:
> type=AVC msg=audit(...): avc:  denied  { getopt } for  pid=... scontext=system_u:system_r:mysvcd_t:s0 ... comm="mysvcd" ... tclass=tcp_socket ...

### 2. Verify Running Context

Ensure the service runs under the intended domain (if it is operating even partially):
```bash
ps -axZ | grep [m]ysvcd
```
Expected output:
```
system_u:system_r:mysvcd_t:s0 ...
```

### 3. Check Policy Permissions

List all active permissions for the domain:
```bash
sesearch --allow -s mysvcd_t
```
> This command shows the list of permissions currently active for the domain as loaded in the system policy.  
> It will reveal rules that are missing, not loaded, or not taking effect for any reason. In troubleshooting, this step is crucial for verifying that your intended policy is actually enforced—if a rule is absent here, your module may not be fully loaded, or the source `.te` file may have different permission rules or parameters than you actually intended.

Specifically check for the problematic permission if required:
```bash
sesearch --allow -s mysvcd_t -t mysvcd_t -c tcp_socket
```
> `-s`(`--source`): source type/attr name, `-t`(`--target`): target type/attr, `-c`(`--class`): object class 

**Expected (correct) output:**
```
allow mysvcd_t mysvcd_t:tcp_socket { connect create getopt };
```
**If missing `getopt`:**
```
allow mysvcd_t mysvcd_t:tcp_socket { connect create };
```

> 📝 **About `self` in policy rules:**  
> In SELinux policy, the keyword `self` is used to refer to the case where both the source and target are the same domain/type. For example,  
> ```te
> allow mysvcd_t self:tcp_socket { create connect getopt };
> ```
> is shorthand for  
> ```te
> allow mysvcd_t mysvcd_t:tcp_socket { create connect getopt };
> ```
> This matches rules where both `scontext` and `tcontext` are set to `mysvcd_t` in audit logs.

---

## Resolution Steps

### 1. Update Policy Source

Examine your source `.te` file to ensure the permission rule exists and includes all required *operations* (*permissions*); for example:
```te
allow mysvcd_t self:tcp_socket { create connect };
```
Correct to:
```te
allow mysvcd_t self:tcp_socket { create connect getopt };
```

Also verify that the preceding `require {}` clause declares all necessary `type`, `class`, `attribute`, etc. for the rules. If you omit something, policy compilation or installation will fail or the rule won't be effective.  
These missing references are usually highlighted in AVC denial messages.

> 💡 **Tips:** If domain transition (changing from one SELinux domain/type to another, mainly used to activate an executable via `Systemd`/`SysVinit`) is not working as expected, check that you have declared the correct `role` in your policy and that your process is allowed to enter the target domain under that role.  
> In SELinux, both the `role` and `type` must be authorized for transitions to succeed. Missing or misconfigured role declarations are a common source of unexpected transition failures.

### 2. Rebuild and Reload Policy

```bash
checkmodule -M -m -o mysvcd.mod mysvcd.te
semodule_package -o mysvcd.pp -m mysvcd.mod
semodule -v -X 300 -i mysvcd.pp
```

> 💡 **Tips: Overwriting vs. Removing Policy Modules**  
> You can overwrite your installed SELinux policy module by simply reinstalling (`semodule -i`). There is **no need to remove the module first**.  
> In fact, removing a module without resetting labels on associated directories/files can sometimes lead to problems where modules become unremovable or leave remnants.  
> **Recommendation:** Always update by overwriting unless you are intentionally purging all traces of a module.

**Checking Loaded Modules:**  
After installing, you can confirm the module is loaded and its types are present by running:
```bash
semodule -lfull | grep mysvcd && seinfo -xt | grep mysvcd
```
This will list the loaded SELinux module(s) and show the defined types.

> 💡 **Tips:** If you perform these steps often, consider scripting them for convenience.  
> Example shell script (`build-mysvcd.sh`):
> ```sh
> #!/bin/sh
> show_run () {
>     echo $@ ; $@
> }
> 
> show_run checkmodule -M -m -o mysvcd.mod mysvcd.te
> show_run semodule_package -o mysvcd.pp -m mysvcd.mod
> 
> echo "## Run below to install and check the SE-module:"
> cat <<EOM
> semodule -v -X 300 -i mysvcd.pp
> semodule -lfull | grep mysvcd && seinfo -xt | grep mysvcd
> EOM
> ```
> This automates routine builds and reminds you how to verify installation.

📝 **Note:** When you remove or overwrite a module, also consider whether filesystem labels need to be reset (`restorecon` or `semanage fcontext`), especially when changing types or paths. If your want to check if it applies to your case, refer to [Uninstalling Policy Modules](selinux-create-own-service-policy.md#uninstalling-policy-modules-when-needed) in the related document [Create SELinux Policy Module for Your Own Service](selinux-create-own-service-policy.md).

### 3. Verify Policy is Active

Check again with `sesearch`:
```bash
sesearch --allow -s mysvcd_t -t mysvcd_t -c tcp_socket
```
Confirm the operation `getopt` is now present.

### 4. Test Service Behavior

- Start the service.
- Monitor audit logs and the service’s own logs.
- Use `netstat` to confirm connection attempts.
- Stop the service, and check audit again; In some cases, different denials occur on service shutdown.
- If the policy is correct and loaded, audit denials should cease for the permitted operation.

### 5. If Not Solved or Another Denial is Observed

Repeat the diagnostics process starting from Step 1.

> 💡 **Tips: Troubleshooting Sequential Permission Errors**  
> If you encounter a series of SELinux denials—where resolving one permission leads to another denial—consider temporarily switching the system to **Permissive mode**:
> ```bash
> setenforce 0
> getenforce
> ```
> In Permissive mode, SELinux logs denials but does not block operations. This lets you run the service and collect a complete list of required permissions from the audit logs.
> **Be sure to return to Enforcing mode** after you have corrected the policy:
> ```bash
> setenforce 1
> ```

---

## Key Lessons

- **Always verify the active policy** with `sesearch` after making changes.
- Even if you believe your `.te` file is correct, it is best to rebuild and reinstall the module to ensure any changes take effect.
- Use both audit logs and SELinux policy tools for comprehensive troubleshooting.
- When in doubt, make incremental changes and keep backups of your working policy files.
- Document each step—future you will thank you!

---

## References

- `ausearch(8)`: Audit log search tool  
- `sesearch(1)`: SELinux policy rule search tool  
- `semodule(8)`: SELinux policy module management  
- [SELinux - Gentoo Wiki](https://wiki.gentoo.org/wiki/SELinux)
