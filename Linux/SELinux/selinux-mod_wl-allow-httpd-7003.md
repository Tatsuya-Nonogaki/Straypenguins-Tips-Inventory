# Manage SELinux to Allow httpd to Access Port 7003/TCP
## Overview

**This document provides practical, adaptable steps for customizing SELinux policy to securely enable `httpd` to establish outbound access to non-standard network port, e.g., 7003/TCP.**

**Related Documents**
- [Create SELinux Policy Module for Your Own Service](selinux-create-own-service-policy.md)
- [SELinux Policy Troubleshooting: Resolving Audit Denials for a Custom Service](selinux-service-policy-troubleshooting.md)

---

## Install Prerequisite Packages (RHEL9)

```bash
dnf install policycoreutils-devel selinux-policy-devel
# Optional:
dnf install setools-console
```

---

## See What Is Going On

Search for SELinux denials for the httpd process:
```bash
ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR | grep httpd
```
In the output, look for `denied { ... }` and `tclass=...` entries.

For alternative audit log search methods (exact process matching, filtering by time, etc.), see the [Audit Log Search Cheat Sheet](selinux-service-policy-troubleshooting.md#1-identify-denied-operations).

If relevant denials are found, proceed to the policy customization or troubleshooting sections below.

---

## Customize the Policy —Automatic Way (Moderate Security - All `unreserved_ports` Are Allowed from httpd)

> **Caution:**  
> When filtering audit logs for use with `audit2allow`, be aware that narrowing results with the `-m` option (e.g., `-m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR`) may accidentally exclude relevant SELinux denial messages, especially if your system logs additional or unexpected types.  
> For best results, omit the `-m` option when piping `ausearch` output to `audit2allow`; the tool will automatically ignore unrelated messages and process all necessary SELinux denials.

### Preview the Resultant Rule

```bash
ausearch -c httpd | audit2allow -R
```

### Prepare Module Directory

Create a directory with arbitrary name:
```bash
mkdir -p myhttpd_mod_wl-audo
cd myhttpd_mod_wl-auto
```

### Auto-Generate Policy Module

```bash
ausearch -c httpd --raw | audit2allow -M myhttpd_mod_wl
ls -l
```

You should see `myhttpd_mod_wl.te` (policy source text) and `myhttpd_mod_wl.pp` (compiled policy module) were created.

---

### Install Policy Module

```bash
semodule -v -X 300 -i myhttpd_mod_wl.pp
```

Verify installation
```bash
semodule -lfull | grep myhttpd_mod_wl
ls -l /var/lib/selinux/targeted/active/modules/*/myhttpd_mod_wl
```

Check actual permission rule
```bash
sesearch --allow -s httpd_t -t unreserved_port_t -c tcp_socket -p name_connect
```

---

## Customize the Policy —Organized Way (More Secure and controllable)

### Create Port-Type Module

#### 1. Check if Port 7003 is Assigned

If the outbound network port in question is wel-known and commonly used one, you have no choice; use predefined type name. Also, if the port is not defined on your OS, you have to define a new type. On the other hand, you need to consider whether to use predefined one or to re-define the port-type with a new name, when the port is unused and rerely used one.

```bash
semanage port -l | grep -w '700[0-9]' | grep tcp
```

Example output:

```
afs3_callback_port_t           tcp      7001
afs_pt_port_t                  tcp      7002
gatekeeper_port_t              tcp      1721, 7000
```

**Check for Multiple Ports or Ranges (See also [Tips: Expand Port Ranges](#tips-expand-port-ranges))**

```bash
echo $(semanage port -l | awk '$1=="afs3_callback_port_t" && $2=="tcp" {$1=$2=""; print $0}')
```

#### ⚠️ Safety Check Before Deleting Port Assignment

If you need to assign a custom SELinux port type label to a port that is already associated with another type, you must first delete the existing assignment. **However, never delete a port assignment unless you are certain it is not required by any running service or SELinux policy.**

Follow these steps before deleting:

1. **Find the SELinux type mapped to the port (7003/TCP for example):**
    ```bash
    semanage port -l | grep -w '7003' | grep tcp
    # Note the SELinux type in the first column of the output.
    ```

2. **Check which SELinux domains are allowed to use this type:**
    Replace `<SELinux_port_type>` with the type found above (e.g., `afs3_callback_port_t`):
    ```bash
    sesearch --allow -t <SELinux_port_type> -c tcp_socket -p name_connect
    sesearch --allow -t <SELinux_port_type> -c tcp_socket -p name_bind
    ```

3. **Check if any process is actively using the port:**
    ```bash
    netstat -lntp | grep ':7003'
    # Find the PID, then check its SELinux context:
    ps -Z -p <pid>
    # Make sure the running process is not using a domain that needs this port type
    ```

#### 2. Delete Existing Assignment *If Safe to Do*

If you have confirmed the port is not in use:

```bash
semanage port -d -p tcp 7003
```

**Otherwise, reuse the predefined port-type.**

---

#### Tips: Expand Port Ranges

```bash
semanage port -l | awk '$1=="afs3_callback_port_t" && $2=="tcp" {$1=$2=""; print $0}' | \
  tr ',' '\n' | while read p; do
    if [[ "$p" == *-* ]]; then seq ${p%-*} ${p#*-}; else echo $p; fi
done
```

---

#### 3. Build and Install Port-Type Module

**Prepare Module Directory with arbitrary name:**

```bash
mkdir -p myhttpd_mod_wl
cd myhttpd_mod_wl
```

**Create policy module source `.te` file: `myhttpd_wls_type.te`**

```te
module myhttpd_wls_type 1.0;

require {
    attribute port_type;
}

type httpd_wls_port_t;
typeattribute httpd_wls_port_t port_type;
```

> **Use Underscores in Names!**  
> Avoid using dashes (`-`), dots (`.`), or other punctuation for word separation in SELinux type names. These characters can prevent SELinux policies from working properly or may cause errors during policy compilation.

**Build and Install Module**

```bash
checkmodule -M -m -o myhttpd_wls_type.mod myhttpd_wls_type.te
semodule_package -o myhttpd_wls_type.pp -m myhttpd_wls_type.mod
semodule -v -X 300 -i myhttpd_wls_type.pp
```

Verify installation
```bash
semodule -lfull | grep myhttpd_wls_type
```

---

### Create Main Module

#### 1. Build and Install Main Module

**Create policy module source `.te` file: `myhttpd_mod_wl.te`**

```te
module myhttpd_mod_wl 1.0;

require {
    type httpd_t;
    type httpd_wls_port_t;
    class tcp_socket name_connect;
}

allow httpd_t httpd_wls_port_t:tcp_socket name_connect;
```

Alternatively, if you decided to reuse predefined port-type (e.g. 7001:`afs3_callback_port_t`):

```te
module myhttpd_mod_wl 1.0;

require {
    type httpd_t;
    type afs3_callback_port_t;
    class tcp_socket name_connect;
}

allow httpd_t afs3_callback_port_t:tcp_socket name_connect;
```

The above two element can be blended (using both or more).

**Build and Install Module**

```bash
checkmodule -M -m -o myhttpd_mod_wl.mod myhttpd_mod_wl.te
semodule_package -o myhttpd_mod_wl.pp -m myhttpd_mod_wl.mod
semodule -v -X 300 -i myhttpd_mod_wl.pp
```

Verify installation
```bash
semodule -lfull | grep myhttpd_mod_wl
ls -l /var/lib/selinux/targeted/active/modules/*/myhttpd_mod_wl
```

Check actual permission rule
```bash
sesearch --allow -s httpd_t -t httpd_wls_port_t -c tcp_socket -p name_connect
```

---

### Port Assignment (required only when Manual Build)

```bash
semanage port -a -t httpd_wls_port_t -p tcp 7003
```

Verify Assignment

```bash
echo $(semanage port -l | awk '$1=="httpd_wls_port_t" && $2=="tcp" {$1=$2=""; print $0}')
```

---

## Start Service and Verify

Start httpd via systemd and check logs:

```bash
systemctl start httpd.service
```

Go back to [See What Is Going On](#see-what-is-going-on) to check denials in AVC.

---

## Uninstall the Module (if you ought to do in the future...)

Stop httpd service and follow the steps below.

### Remove port-type module:
```bash
semodule -v -X 300 -r myhttpd_wls_type
semodule -lfull | grep myhttpd_wls_type
```

### Remove main module:

```bash
semodule -v -X 300 -r myhttpd_mod_wl
semodule -lfull | grep myhttpd_mod_wl
```
