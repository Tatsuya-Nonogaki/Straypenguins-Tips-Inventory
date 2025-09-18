# Manage SELinux to Allow httpd to Access Port 7003/TCP

## Overview

This document provides practical, adaptable steps for customizing SELinux policy to securely enable `httpd` to establish outbound access to a non-standard network port, e.g., 7003/TCP.

**Related Documents**
- [Create SELinux Policy Module for Your Own Service](selinux-create-own-service-policy.md)
- [SELinux Policy Troubleshooting: Resolving Audit Denials for a Custom Service](selinux-service-policy-troubleshooting.md)

---

## Procedure Outline

- [Install Prerequisite Packages (RHEL9)](#install-prerequisite-packages-rhel9)
- [See What Is Going On](#see-what-is-going-on)
- [Customize the Policy —Automatic Way (Moderate Security - All `unreserved_ports` Are Allowed from httpd)](#customize-the-policy—automatic-way-moderate-security---all-unreserved_ports-are-allowed-from-httpd)
    - [Preview the Resultant Rule](#preview-the-resultant-rule)
    - [Prepare Module Directory](#prepare-module-directory)
    - [Auto-Generate Policy Module](#auto-generate-policy-module)
    - [Install Policy Module](#install-policy-module)
- [Customize the Policy —Organized Way (More Secure and controllable)](#customize-the-policy—organized-way-more-secure-and-controllable)
    - [Create Port-Type Module](#create-port-type-module)
        - [1. Check if Port 7003 is Assigned](#1-check-if-port-7003-is-assigned)
        - [2. Delete Existing Assignment *If Safe to Do*](#2-delete-existing-assignment-if-safe-to-do)
        - [3. Build and Install Port-Type Module](#3-build-and-install-port-type-module)
    - [Create Main Module](#create-main-module)
        - [1. Build and Install Main Module](#1-build-and-install-main-module)
    - [Port Assignment (required only when Manual Build)](#port-assignment-required-only-when-manual-build)
- [Start Service and Verify](#start-service-and-verify)
- [Uninstall the Modules (When Needed)](#uninstall-the-modules-when-needed)
    - [Remove port-type module](#remove-port-type-module)
    - [Remove main module](#remove-main-module)

---

## Install Prerequisite Packages (RHEL9)

```bash
dnf install policycoreutils-devel selinux-policy-devel
# Optional:
dnf install setools-console
```

---

## See What Is Going On

Search for SELinux denials related to the httpd process:

```bash
ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR | grep httpd
```

In the output, look for `denied { ... }` and `tclass=...` entries.  
If relevant denials are found, proceed to the policy customization or troubleshooting sections below.

> 👉 For alternative audit log search methods (exact process matching, filtering by time, etc.), see [Audit Log Search Cheat Sheet](selinux-service-policy-troubleshooting.md#1-identify-denied-operations) in the related document: [SELinux Policy Troubleshooting](selinux-service-policy-troubleshooting.md).

---

## Customize the Policy — Automatic Way (Moderate Security: Allow All `unreserved_ports` from httpd)

> ⚠️ **Caution:**  
> When filtering audit logs for use with `audit2allow`, be aware that using the `-m` option (e.g., `-m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR`) may accidentally exclude relevant SELinux messages.  
> For best results, omit the `-m` option when piping `ausearch` output to `audit2allow`; the tool will ignore unrelated messages and process all necessary SELinux denials.

### Preview the Resultant Rule

```bash
ausearch -c httpd | audit2allow -R
```

### Prepare Module Directory

Create a working directory (use any name you like):

```bash
mkdir -p myhttpd_mod_wl-auto
cd myhttpd_mod_wl-auto
```

### Auto-Generate Policy Module

```bash
ausearch -c httpd --raw | audit2allow -M myhttpd_mod_wl
ls -l
```

You should see `myhttpd_mod_wl.te` (policy source) and `myhttpd_mod_wl.pp` (compiled module) created.

---

### Install Policy Module

```bash
semodule -v -X 300 -i myhttpd_mod_wl.pp
```

Verify installation:

```bash
semodule -lfull | grep myhttpd_mod_wl
ls -l /var/lib/selinux/targeted/active/modules/*/myhttpd_mod_wl
```

Check the actual permission rule:

```bash
sesearch --allow -s httpd_t -t unreserved_port_t -c tcp_socket -p name_connect
```

---

## Customize the Policy — Organized Way (More Secure and Controllable)

### Create Port-Type Module

#### 1. Check if Port 7003 is Assigned

If the outbound port is well-known and commonly used, you must use the predefined type name. If the port is not defined on your OS, you will need to define a new type, or you may wish to assign your own type name for clarity or future maintenance.

```bash
semanage port -l | grep -w '700[0-9]' | grep tcp
```

Example output:

```
afs3_callback_port_t           tcp      7001
afs_pt_port_t                  tcp      7002
gatekeeper_port_t              tcp      1721, 7000
```

**Check for Multiple Ports or Ranges (See also [Tips: Expand Port Ranges](#-tips-expand-port-ranges))**

```bash
echo $(semanage port -l | awk '$1=="afs3_callback_port_t" && $2=="tcp" {$1=$2=""; print $0}')
```

#### 2. Delete Existing Assignment *If Safe to Do*

⚠️ **Never delete a port assignment without confirming it is not actively used by another domain.**

**2-1. Safety Check Before Deleting Port Assignment**

If you need to assign a custom SELinux port type to a port already associated with another type, you must first delete the existing assignment.  
Follow these steps before deleting:

2-1-1. Find the SELinux type mapped to the port (e.g., 7003/TCP):  
    ```bash
    semanage port -l | grep -w '7003' | grep tcp
    # Note the SELinux type in the first column of the output.
    ```

2-1-2. Check which SELinux domains are allowed to use this type:  
   Replace `<SELinux_port_type>` with the type found above (e.g., `afs3_callback_port_t`):
    ```bash
    sesearch --allow -t <SELinux_port_type> -c tcp_socket -p name_connect
    sesearch --allow -t <SELinux_port_type> -c tcp_socket -p name_bind
    ```

2-1-3. Check if any process is actively using the port:  
    ```bash
    netstat -lntp | grep ':7003'
    # Find the PID, then check its SELinux context:
    ps -Z -p <pid>
    # Ensure the running process is not using a domain that needs this port type.
    ```

**2-2. If you have confirmed the port is not in use:**

```bash
semanage port -d -p tcp 7003
```

**Otherwise, reuse the predefined port type.**

---

#### 💡 Tips: Expand Port Ranges

```bash
semanage port -l | awk '$1=="afs3_callback_port_t" && $2=="tcp" {$1=$2=""; print $0}' | \
  tr ',' '\n' | while read p; do
    if [[ "$p" == *-* ]]; then seq ${p%-*} ${p#*-}; else echo $p; fi
done
```

---

#### 3. Build and Install Port-Type Module

**Prepare a module directory (use any name you like):**

```bash
mkdir -p myhttpd_mod_wl
cd myhttpd_mod_wl
```

**Create the policy module source `.te` file: `myhttpd_wls_type.te`**

```te
module myhttpd_wls_type 1.0;

require {
    attribute port_type;
}

type httpd_wls_port_t;
typeattribute httpd_wls_port_t port_type;
```

> ⚠️ **Use Underscores in Names**  
> Avoid using dashes (`-`), dots (`.`), or other punctuation for word separation in SELinux type names. These characters can prevent SELinux policies from working properly or may cause errors during policy installation.

**Build and Install the Module**

```bash
checkmodule -M -m -o myhttpd_wls_type.mod myhttpd_wls_type.te
semodule_package -o myhttpd_wls_type.pp -m myhttpd_wls_type.mod
semodule -v -X 300 -i myhttpd_wls_type.pp
```

Verify installation:

```bash
semodule -lfull | grep myhttpd_wls_type
```

---

### Create Main Module

#### 1. Build and Install Main Module

**Create the policy module source `.te` file: `myhttpd_mod_wl.te`**

```te
module myhttpd_mod_wl 1.0;

require {
    type httpd_t;
    type httpd_wls_port_t;
    class tcp_socket name_connect;
}

allow httpd_t httpd_wls_port_t:tcp_socket name_connect;
```

Alternatively, if you decide to reuse a predefined port type (e.g., 7001: `afs3_callback_port_t`):

```te
module myhttpd_mod_wl 1.0;

require {
    type httpd_t;
    type afs3_callback_port_t;
    class tcp_socket name_connect;
}

allow httpd_t afs3_callback_port_t:tcp_socket name_connect;
```

You can blend the above if you want to allow more than one port type.

**Build and Install the Module**

```bash
checkmodule -M -m -o myhttpd_mod_wl.mod myhttpd_mod_wl.te
semodule_package -o myhttpd_mod_wl.pp -m myhttpd_mod_wl.mod
semodule -v -X 300 -i myhttpd_mod_wl.pp
```

Verify installation:

```bash
semodule -lfull | grep myhttpd_mod_wl
ls -l /var/lib/selinux/targeted/active/modules/*/myhttpd_mod_wl
```

Check the actual permission rule:

```bash
sesearch --allow -s httpd_t -t httpd_wls_port_t -c tcp_socket -p name_connect
```

---

### Port Assignment (Required Only When Manual Build)

```bash
semanage port -a -t httpd_wls_port_t -p tcp 7003
```

Verify assignment:

```bash
echo $(semanage port -l | awk '$1=="httpd_wls_port_t" && $2=="tcp" {$1=$2=""; print $0}')
```

---

## Start Service and Verify

Start the httpd service and check logs:

```bash
systemctl start httpd.service
```

Return to [See What Is Going On](#see-what-is-going-on) to check for AVC denials.

---

## Uninstall the Modules (When Needed)

Stop the httpd service, then follow the steps below.

### Remove Port-Type Module:

```bash
semodule -v -X 300 -r myhttpd_wls_type
semodule -lfull | grep myhttpd_wls_type
```

### Remove Main Module:

```bash
semodule -v -X 300 -r myhttpd_mod_wl
semodule -lfull | grep myhttpd_mod_wl
```

> 👉 For more complex uninstall scenarios—such as multi-module dependencies or thorough label cleanup—refer to  
> [Uninstalling Policy Modules (When Needed)](selinux-create-own-service-policy.md#uninstalling-policy-modules-when-needed)  
> in the related document: [Create SELinux Policy Module for Your Own Service](selinux-create-own-service-policy.md).
