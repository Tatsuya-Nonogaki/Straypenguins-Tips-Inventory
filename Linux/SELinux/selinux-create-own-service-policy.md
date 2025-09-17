# Create SELinux Policy Module for Your Own Service

## Overview

This document explains how to design, implement, test, and maintain custom SELinux policy modules for your own services on RHEL/CentOS 9 systems.  
You will learn how to:

- Decide when to use a predefined port type or create your own.
- Write a modular SELinux policy—splitting service and data access into separate, maintainable modules.
- Build, install, and label files for each module.
- Troubleshoot policy denials and verify correct operation.
- Cleanly uninstall your policy modules, respecting inter-module dependencies.

**Related Documents**
- [Manage SELinux to Allow httpd to Access Port 7003/TCP](selinux-mod_wl-allow-httpd-7003.md)
- [SELinux Policy Troubleshooting: Resolving Audit Denials for a Custom Service](selinux-service-policy-troubleshooting.md)

---

## Environment &amp; Specification

- **Service:** `/opt/mysvc/bin/mysvcd`
- **SELinux domain:** `mysvcd_t`
- **SELinux status:** Enforcing
- **Network access:** Outbound connection to `x.x.x.x:443/TCP` (or `:7001/TCP`)

---

### Glossary

- **Domain/type:** SELinux security label assigned to a process (e.g., `mysvcd_t`)
- **Class:** SELinux object class (e.g., `tcp_socket`, `file`)
- **Permission/operation:** Specific allowed actions for a class (e.g., `connect`, `getopt`)
- **Policy module:** Packaged SELinux policy rules for installation (`.pp` file, typically built from `.te` (Type Enforcement) and other sources like `.if`, `.fc`, etc.)

---

## Install Prerequisite Packages (RHEL9)

```bash
dnf install policycoreutils-devel selinux-policy-devel
# Optional:
dnf install setools-console
```

---

## Decide Between Predefined Port Type or Creating Your Own

When enabling SELinux access to outbound ports, you have two options:

- **Use an existing predefined port type** (e.g., `http_port_t` for 443/TCP), if it matches your security intent.
- **Create your own port type** if:
    - There is no suitable predefined type for the port you need.
    - You prefer to assign a custom type for clarity or future maintenance, even if the port is already associated with a rarely-used predefined type.
    - You want to clear an old mapping and define your own.

To check if your desired port is already associated with a type:

```bash
semanage port -l | grep -w '700[0-9]' | grep tcp
```

Example output:

```
afs3_callback_port_t           tcp      7001
afs_pt_port_t                  tcp      7002
gatekeeper_port_t              tcp      1721, 7000
```

If your port is **not listed**, or **you wish to assign your own type name**, see  
[Manage SELinux to Allow httpd to Access Port 7003/TCP](selinux-mod_wl-allow-httpd-7003.md)  
for instructions on defining or reassigning a port type.

> This document proceeds with two cases:
> - Predefined `http_port_t` : 443/TCP
> - Custom `httpd_wls_port_t` : 7001/TCP (requires building/installing a port policy module before proceeding)

---

## Create Domain Type Module for Custom Executable

### 1. Create Policy Module Source `.te` File

This is the **main module**, defining Exec type and Domain type, with transition for systemd.  
👉 *Supplementary type definitions and permissions go into a separate [Storage Module](#create-a-supplementary-module-storage-module).*

**File: `mysvcd.te`**  
*Replace `http_port_t` with `httpd_wls_port_t` if you use 7001/TCP.*

```te
module mysvcd 1.0;

require {
    type init_t;
    type http_port_t;
    type fs_t;
    attribute domain;
    attribute exec_type;
    attribute file_type;
    attribute non_auth_file_type;
    attribute non_security_file_type;
    class filesystem getattr;
    class tcp_socket { create connect name_connect getopt };
    class process { transition };
    class file { open read write append execute create unlink map getattr entrypoint };
    class dir { open read write getattr search add_name remove_name };
    class lnk_file read;
    role system_r;
}

type mysvcd_t, domain;

type mysvcd_exec_t;
typeattribute mysvcd_exec_t exec_type, file_type, non_auth_file_type, non_security_file_type;

type mysvcd_opt_t;
typeattribute mysvcd_opt_t file_type, non_auth_file_type, non_security_file_type;

# Entrypoint & transition
role system_r types mysvcd_t;
allow init_t mysvcd_exec_t:file { read open execute map };
type_transition init_t mysvcd_exec_t:process mysvcd_t;
allow init_t mysvcd_t:process transition;

# Entrypoint and full access to service executable for transition and execution
allow mysvcd_t mysvcd_exec_t:file { entrypoint read open execute map getattr };

# Access to own libraries and symlinks
allow mysvcd_t mysvcd_opt_t:file { read open execute map getattr };
allow mysvcd_t mysvcd_opt_t:lnk_file read;

# Network
allow mysvcd_t http_port_t:tcp_socket name_connect;
allow mysvcd_t self:tcp_socket { create connect getopt };

# Filesystem (e.g., /):
allow mysvcd_t fs_t:filesystem getattr;

# Service package home access
allow mysvcd_t mysvcd_opt_t:dir { read search write add_name remove_name getattr open };
allow mysvcd_t mysvcd_opt_t:file { read write append open create unlink map getattr };
```

### 2. Build and Install Domain Module

```bash
checkmodule -M -m -o mysvcd.mod mysvcd.te
semodule_package -o mysvcd.pp -m mysvcd.mod
semodule -v -X 300 -i mysvcd.pp
semodule -lfull | grep mysvcd
```

### 3. Label Your Executable and Package Home Directory

```bash
semanage fcontext -a -t mysvcd_exec_t "/opt/mysvc/mysvcd"
restorecon -Fv /opt/mysvc/mysvcd

semanage fcontext -a -t mysvcd_opt_t "/opt/mysvc(/.*)?"
restorecon -FRv /opt/mysvc/
```

---

## Create a Supplementary Module (Storage Module)

This guide recommends a modular SELinux policy design:
- The **core policy module** covers service executable and home directories.
- The **supplementary "storage" module** grants access to variable data or shared directories (e.g., `/var/log/mysvc/`, `/var/cache/mysvc/`, `/var/lib/mysvc/`).

💡 **Best Practice:**  
Handle access to variable/shared directories in a dedicated supplementary module to keep policy maintainable, flexible, and easier to troubleshoot.

### 1. Create Policy Module Source `.te` for Storage

**File: `mysvcd_storage.te`**

*For accessing files/directories with predefined/shared labels:*

```te
module mysvcd_storage 1.0;

require {
    type mysvcd_t;
    type var_log_t;
    class dir { read search write add_name remove_name };
    class file { read write append open create unlink };
}

allow mysvcd_t var_log_t:dir { read search write add_name remove_name };
allow mysvcd_t var_log_t:file { read write append open create unlink };
```

*Or, for dedicated labels for your service’s variable files/directories:*

```te
module mysvcd_storage 1.0;

require {
    type mysvcd_t;
    class dir { read search write add_name remove_name };
    class file { read write append open create unlink };
}

# Define a dedicated type for all (or split by purpose, see above)
type mysvcd_var_t;
files_type(mysvcd_var_t)

allow mysvcd_t mysvcd_var_t:dir { read search write add_name remove_name };
allow mysvcd_t mysvcd_var_t:file { read write append open create unlink };
```

> 💡 **Type Granularity:**  
> The module example above uses one single *catch-all* type `mysvcd_var_t` for all variable data. Alternatively if you want stricter access control, you can define more granular types, e.g., `mysvcd_var_log_t` for logs, `mysvcd_var_cache_t` for cache, etc.

### 2. Build and Install Storage Module

```bash
checkmodule -M -m -o mysvcd_storage.mod mysvcd_storage.te
semodule_package -o mysvcd_storage.pp -m mysvcd_storage.mod
semodule -v -X 300 -i mysvcd_storage.pp
semodule -lfull | grep mysvcd_storage
```

### 3. Label Variable Directories and Files

```bash
semanage fcontext -a -t mysvcd_var_t "/var/log/mysvc(/.*)?"
semanage fcontext -a -t mysvcd_var_t "/var/cache/mysvc(/.*)?"
semanage fcontext -a -t mysvcd_var_t "/var/lib/mysvc(/.*)?"
restorecon -FRv /var/log/mysvc/ /var/cache/mysvc/ /var/lib/mysvc/
```

**You can build, install, and update these modules independently as your package requirements evolve.**

---

## Start with Systemd and Verify

Start your service via systemd, and check the running process label:

```bash
systemctl start mysvcd.service
ps -Z -C mysvcd
```
Expected: `mysvcd_t` should appear in the process label.

Check for SELinux denials using `ausearch`:
```bash
ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR -su mysvcd_t
```
For more audit log search options and tips, see the [Audit Log Search Cheat Sheet](selinux-service-policy-troubleshooting.md#1-identify-denied-operations).

If any denials are observed, start diagnostics; consult the related document:  
[SELinux Policy Troubleshooting: Resolving Audit Denials for a Custom Service](selinux-service-policy-troubleshooting.md)

---

## Uninstalling Policy Modules (When Needed)

When you need to remove your custom SELinux policy modules, follow this procedure for a clean uninstall.

### Considerations Before Committing Module Removal

- **Do Not Remove Modules While They Are In Use**

  Removing a module while it is still in use can cause uninstall errors or leave files with “orphaned” labels that SELinux no longer recognizes.

  - Ensure the service/program using the policy is stopped and disabled.
  - Reset any labels defined by the module you intend to remove from all affected files or directories.

- **Removal Order Depends on Module Dependencies**

  - When multiple modules are involved, remove them in an order that respects their dependencies.
  - Review the `allow` and `type` statements in your modules to determine these dependencies.

### 1. Stop the Service

Stop and disable the service to ensure no processes are using the policy modules.

```bash
systemctl stop mysvcd
systemctl disable mysvcd
```

### 2. Remove the Storage Policy Module

In this example, the supplementary module `mysvcd_storage` depends on the main module `mysvcd`.  
The `mysvcd_storage` module contains permission rules such as `allow mysvcd_t ...`, where `mysvcd_t` is a type/domain defined in the main module.  
The main module cannot be safely removed until the storage module is uninstalled.

#### 2-1. Reset File Labels

Remove any custom file context assignments and restore default SELinux labels for data directories.

```bash
semanage fcontext -d "/var/log/mysvcd"
semanage fcontext -d "/var/log/mysvc(/.*)?"
restorecon -RFv /var/log/mysvcd
```

Verify the reset:
```bash
ls -ldZ /var/log/mysvcd
ls -lZ /var/log/mysvcd
```

#### 2-2. Uninstall the Storage Policy Module

Remove the storage-related policy module.

```bash
semodule -v -X 300 -r mysvcd_storage
semodule -lfull | grep mysvcd_storage
```

### 3. Remove the Main Policy Module

Now proceed to remove your main custom policy module.

#### 3-1. Reset File Labels

Reset custom file types for executables and primary package directories.  
This is required if your main policy module defined its own file types.

```bash
restorecon -Fv /opt/mysvc/bin/mysvcd
chcon -t bin_t /opt/mysvc/bin/mysvcd

semanage fcontext -d "/opt/mysvc/bin/mysvcd"
semanage fcontext -d "/opt/mysvc(/.*)?"

restorecon -RFv /opt/mysvc
```

Verify the reset:
```bash
ls -ldZ /opt/mysvc
ls -lZ /opt/mysvc
```

#### 3-2. Uninstall the Main Policy Module

Remove the main policy module.

```bash
semodule -v -X 300 -r mysvcd
semodule -lfull | grep mysvcd
```
