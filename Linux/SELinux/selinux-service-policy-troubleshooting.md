# SELinux Policy Troubleshooting: Resolving Audit Denials for a Custom Service

## Overview

This document demonstrates the investigation, diagnosis, and resolution steps for SELinux policy denials encountered by a custom service/domain (e.g., `mysvcd_t`). It describes how to identify, analyze, and resolve permission problems—using a workflow and troubleshooting checklist that can be adapted for various SELinux modules by substituting the relevant domain/type and permissions.

**Related Documents**
- [Manage SELinux to Allow httpd to Access Port 7003/TCP](selinux-mod_wl-allow-httpd-7003.md)
- [Create SELinux Policy Module for Your Own Service](selinux-create-own-service-policy.md)

---

### Glossary

- **Domain/type:** The SELinux security label assigned to a process (e.g., `mysvcd_t`)
- **Class:** SELinux object class (e.g., `tcp_socket`, `file`)
- **Permission/operation:** Specific allowed actions for a class (e.g., `connect`, `getopt`)
- **Policy module:** A packaged set of SELinux policy rules for installation (usually as a `.pp` *(Policy Package)* file, sourced from one or more files like `.te` *(Type Enforcement)*, `.if`, `.fc`, etc.)

---

## Environment & Example Situation

- **Service:** `/opt/mysvc/bin/mysvcd`
- **SELinux domain:** `mysvcd_t`
- **SELinux status:** Enforcing
- **Symptoms:** Repeated audit denials for the `getopt` operation on class `tcp_socket` during outbound connection attempts to `x.x.x.x:443`.

👉 For SELinux-specific terminology, see the [centralized Glossary](README.md#glossary) in the [README.md](README.md) for this folder.

---

## Procedure Outline

- [Diagnostic Steps](#diagnostic-steps)
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

## Diagnostic Steps

### 1. Identify Denied Operations

Check audit logs for SELinux denials using `ausearch`:

```bash
ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR -su mysvcd_t
```

Use `ausearch` to efficiently locate relevant information. Here are some useful patterns:

| Goal                           | Command Example                                                  | Description              |
|---------------------------------|------------------------------------------------------------------|--------------------------|
| All SELinux denials            | `ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR`          | Match message types (case-sensitive)     |
| By process name                | `ausearch -c mysvcd`                                             | Full executable name only (exact match, not partial)       |
| By subject domain/type         | `ausearch -su mysvcd_t`                                          | scontext (SELinux subject context), commonly used to match the domain/type |
| By message type                | `ausearch -m AVC`                                                | AVC: most common denials         |
| By start time (since)          | `ausearch -ts today`<br>`... -ts mm/dd/yy 'HH:MM:SS'`<br>`... -ts recent` *(means 10 min ago)*  | Filter by time   |
| Fuzzy match (with grep)        | `ausearch ... \| grep mysvcd`                                    | Any line with substring             |
| Command prefix match (with grep)| `ausearch ... \| grep 'comm="mysvcd'`                           | Commands starting with name      |

📝 **Note:**
- In the output, look for `denied { ... }` and `tclass=...` to help identify the root cause and solution.
- `-c`/`--comm`: Command name (executable filename), not the policy name.
- `-su`: scontext (SELinux subject context), commonly used to match the domain/type.
- `-m`: Specifies the message type (e.g., `AVC`, `USER_AVC`, etc.). While `-m AVC` is the most common for denials, others like `USER_AVC`, `SELINUX_ERR`, and `USER_SELINUX_ERR` can surface in special cases (user-space denials or SELinux errors).
- Combine options for precise results (e.g., by process and time).
- See [audit(8) man page](https://man7.org/linux/man-pages/man8/ausearch.8.html) for advanced usage.  

  Typical denial entry:  
  > `type=AVC msg=audit(...): avc:  denied  { getopt } for  pid=... scontext=system_u:system_r:mysvcd_t:s0 ... comm="mysvcd" ... tclass=tcp_socket ...`

> 📝 **Note: `dontaudit` rules can hide SELinux denials**  
>  
> If you see that a service behaves differently in Enforcing vs Permissive mode but `ausearch` (or `audit.log`) shows no AVC `denied` records, consider `dontaudit` rules. A number of default SELinux policies use `dontaudit` to suppress noisy, commonly harmless denies — this can hide valuable diagnostic information during policy troubleshooting.  
>  
> **What to know**  
> - Disabling `dontaudit` does **not** change enforcement semantics (it does not convert denies to allows). It only causes the previously suppressed denials to be written to the audit log so you can inspect them.
> - Because many suppressed messages may appear once `dontaudit` is disabled, expect a large increase in audit log volume. Re-enable `dontaudit` when done.  
>  
> **How to check whether `dontaudit` rules exist**  
> - Show the number of `dontaudit` rules (requires `setools-console` package [RHEL]):
>   ```
>   seinfo --dontaudit
>   ```
>   A non-zero count indicates the policy contains `dontaudit` rules.  
>  
> **How to temporarily disable `dontaudit` to capture hidden denials**  
> - Short option (RHEL docs / common shorthand):  
>   ```bash
>   semodule -DB
>   ```
> - Long option (equivalent):  
>   ```bash
>   semodule --disable_dontaudit --build
>   ```
>   After running either command, reproduce the problem and inspect AVC logs.  
>  
> **How to re-enable `dontaudit` (restore normal, quieter logging)**  
> - Short option:  
>   ```bash
>   semodule -B
>   ```
> - Long option (equivalent):  
>   ```bash
>   semodule --enable_dontaudit --build
>   ```
>  
> 📌 **Notes and best practices:**  
> - Perform this procedure in a controlled window (not long-term) to avoid enormous audit logs.
> - After you fix the policy and reload your module, re-enable `dontaudit`.

### 2. Verify Running Context

Ensure the service is running in the intended SELinux domain (if it is running at all):

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
> This command lists the permissions currently active for the domain, as loaded in the system policy.  
> If a rule is missing from the output, something is preventing it from being active—usually a problem in the module source definition or a failed module load.

Check for a specific problematic permission:

```bash
sesearch --allow -s mysvcd_t -t mysvcd_t -c tcp_socket
```
> `-s` (`--source`): source type/attribute name.  
> `-t` (`--target`): target type/attribute name.  
> `-c` (`--class`): object class.

**Expected (correct) output:**
```
allow mysvcd_t mysvcd_t:tcp_socket { connect create getopt };
```
**If missing `getopt`:**
```
allow mysvcd_t mysvcd_t:tcp_socket { connect create };
```

> 📝 **About `self` in policy rules:**  
> In SELinux policy, the `self` keyword refers to the case where both the source and the target are the same domain/type. For example,  
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

Check your source `.te` file to ensure the permission rule exists and includes all required *operations* (*permissions*), for example:

```te
allow mysvcd_t self:tcp_socket { create connect };
```
Correct to:

```te
allow mysvcd_t self:tcp_socket { create connect getopt };
```

Also ensure the preceding `require {}` clause declares all necessary `type`, `class`, `attribute`, etc. for the rules.  
For example, your `.te` file should look like:

```te
require {
    type mysvcd_t;
    class tcp_socket { create connect getopt };
}
allow mysvcd_t self:tcp_socket { create connect getopt };
```

Omitting something required here can cause policy compilation or installation to fail, or the rule to be ignored.  
Missing references are usually highlighted in AVC denial messages.

> 💡 **Tip:**  
> If domain transition (switching from one SELinux domain/type to another, mainly when activating an executable via `systemd`/`SysVinit`) is not working as expected, check that you have declared all `role` and `type` permissions for the transition.  
> Both the `role` and `type` must be authorized for transitions to succeed. Missing or misconfigured role declarations are a common source of unexpected transition failures.

### 2. Rebuild and Reload Policy

```bash
checkmodule -M -m -o mysvcd.mod mysvcd.te
semodule_package -o mysvcd.pp -m mysvcd.mod
semodule -v -X 300 -i mysvcd.pp
```

> 💡 **Tip: Overwriting vs. Removing Policy Modules**  
> You can overwrite your installed SELinux policy module by simply reinstalling it (`semodule -i`). There is **no need to remove the module first**.  
> In fact, removing a module without first resetting labels on associated directories or files can sometimes cause issues—such as modules becoming unremovable or leaving behind remnants.
> **Recommendation:** Always update by overwriting, unless you are intentionally removing all traces of a module.

**Checking Loaded Modules:**  
After installing, confirm the module is loaded and its types are present:

```bash
semodule -lfull | grep mysvcd && seinfo -xt | grep mysvcd
```
This will list the loaded SELinux module(s) and show the defined types.

> 💡 **Tip:**  
> If you perform these steps often, consider scripting them for convenience.  
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

📝 **Note:**  
When you remove or overwrite a module, also consider whether filesystem labels need to be reset (`restorecon` or `semanage fcontext`), especially if you have changed types or paths.  
For details on when and how to reset labels during module uninstallation, see:  
[Uninstall the policy module](selinux-create-own-service-policy.md#uninstall-the-module-if-you-ought-to-do-in-the-future) in [Create SELinux Policy Module for Your Own Service](selinux-create-own-service-policy.md).

### 3. Verify Policy is Active

Check again with `sesearch`:

```bash
sesearch --allow -s mysvcd_t -t mysvcd_t -c tcp_socket
```
Confirm the operation `getopt` is now present.

### 4. Test Service Behavior

- Start the service.
- Monitor both audit logs and the service’s own logs.
- Use `netstat` to confirm connection attempts.
- Stop the service, and check audit logs again (sometimes different denials occur on service shutdown).
- If the policy is correct and loaded, audit denials should cease for the permitted operation.

### 5. If Not Solved or Another Denial is Observed

Repeat the diagnostic process starting from [Step 1](#diagnostic-steps).

> 💡 **Tip: Troubleshooting Sequential Permission Errors**  
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
- Even if you believe your `.te` file is correct, always rebuild and reinstall the module to ensure changes take effect.
- Use both audit logs and SELinux policy tools for thorough troubleshooting.
- When in doubt, make incremental changes and keep backups of the policy files you are actively working on.
- Document each step—your future self will thank you!

---

## References

- `ausearch(8)`: Audit log search tool  
- `sesearch(1)`: SELinux policy rule search tool  
- `semodule(8)`: SELinux policy module management  
- [SELinux - Gentoo Wiki](https://wiki.gentoo.org/wiki/SELinux)
