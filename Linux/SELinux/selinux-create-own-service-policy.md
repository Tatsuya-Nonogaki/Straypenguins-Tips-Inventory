# Create SELinux Policy Module for Your Own service
This document -- preface here

---

## Environment &amp; Example Situation

- **Service:** `/opt/mysvc/bin/mysvcd`
- **SELinux domain:** `mysvcd_t`
- **SELinux status:** Enforcing
- **Symptoms:** Repeated audit denials for operation `getopt` on class `tcp_socket` during outbound connection attempts to `x.x.x.x:443`.

---

### Glossary

- **Domain/type:** SELinux security label assigned to a process (e.g., `mysvcd_t`)
- **Class:** SELinux object class (e.g., `tcp_socket`, `file`)
- **Permission/operation:** Specific allowed actions for a class (e.g., `connect`, `getopt`)
- **Policy module:** Packaged SELinux policy rules for installation (`.pp` *(Policy Package)* file; its source is usually `.te` *(Type Enforcement)*, plus others like `.if`, `.fc`, etc.)

---

## Install Prerequisite Packages (RHEL9)

```bash
dnf install policycoreutils-devel selinux-policy-devel
# Optional:
dnf install setools-console
```

---

## Decide Between Predefined Port-Type or Create One to Use

If the outbound network port your service connects is 443/TCP, you have no choice; use predefined `http_port_t`. Also, if the port is not defined on your OS, you have to define a new type. On the other hand, you need to consider whether to use predefined one or to re-define the port-type with a new name, when the port is unused and rerely used one.

Suppose the port in question is 7001/TCP. Check if it is already defined:

```bash
semanage port -l | grep -w '700[0-9]' | grep tcp
```

Example output:

```
afs3_callback_port_t           tcp      7001
afs_pt_port_t                  tcp      7002
gatekeeper_port_t              tcp      1721, 7000
```

Further procedures to cerate a policy module for a port is a duplicate area with another document. Please refer to;
[Manage SELinux to Allow httpd to Access Port 7003/TCP](selinux-mod_wl-allow-httpd-7003.md)

> This document assumes two cases to proceed with explanation; Your SELinux port-type is one of;
> - Predefined `http_port_t` : 443/TCP
> - Your own  `httpd_wls_port_t` : 7001/TCP (the policy Module must be built and installed to continue the following procedures)

---

## Create a Domain Type Module for Custom Executable

### 1. Define Exec Type and Domain Type, with Transition for systemd

**File: `mysvcd.te`**
> You need to replace `http_port_t` with `httpd_wls_port_t` if you chose to use 7001/TCP instead.
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

# Filesystem (e.g,. /):
allow mysvcd_t fs_t:filesystem getattr;

# service package home access
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

### 3. Label Your Executable and Package Directory

```bash
semanage fcontext -a -t mysvcd_exec_t "/opt/mysvc/mysvcd"
restorecon -Fv /opt/mysvc/mysvcd

semanage fcontext -a -t mysvcd_opt_t "/opt/mysvc(/.*)?"
restorecon -FRv /opt/mysvc/
```

---

### Additional note on other directory to allow your own service to R/W

This guide employs modular design for different groups of files; fundamental access permissions to the dedicated directories for the service itself, and other variable file access. If your service needs to read/write such *shared* directories—as `/var/log/`, `/var/log/mysvc/`, `/var/cache/mysvc/` etc. —it is best practice to manage these in a separate policy module for modularity and future flexibility.

> In this example, we define a *catch-all* type `mysvcd_var_t`. If your service requires more strict separation of log, cache, lib, etc., you can easily split into more granular types (e.g., `mysvcd_var_log_t`, `mysvcd_var_cache_t`, etc.).

**Example .te for variable data directory: `mysvcd_storage.te`:**

For the case files/directories your service accesses are those assigned with predefined/shared labels:

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

On the other hand, if you give a dedicated label for the serivce to the files/directories:

```te
module mysvcd_storage 1.0;

require {
    type mysvcd_t;
    class dir { read search write add_name remove_name };
    class file { read write append open create unlink };
}

# Repeat this pair of definition for each more granular type if required
type mysvcd_var_t;
files_type(mysvcd_var_t)

# Repeat this pair of definition for each more granular type if required
allow mysvcd_t mysvcd_var_t:dir { read search write add_name remove_name };
allow mysvcd_t mysvcd_var_t:file { read write append open create unlink };
```


**Build and install the module:**

```bash
checkmodule -M -m -o mysvcd_storage.mod mysvcd_storage.te
semodule_package -o mysvcd_storage.pp -m mysvcd_storage.mod
semodule -v -X 300 -i mysvcd_storage.pp
semodule -lfull | grep mysvcd_storage
```

**Example labeling and restorecon commands (not required if predefined ports only):**

```bash
semanage fcontext -a -t mysvcd_var_t "/var/log/mysvc(/.*)?"
semanage fcontext -a -t mysvcd_var_t "/var/cache/mysvc(/.*)?"
semanage fcontext -a -t mysvcd_var_t "/var/lib/mysvc(/.*)?"
restorecon -FRv /var/log/mysvc/ /var/cache/mysvc/ /var/lib/mysvc/
```

**You can build, install, and update these modules independently as your package requirements evolve.**

---

## Start and Verify with systemd

Start your service via systemd, and check the running process label:

```bash
systemctl start mysvcd.service
ps -Z -C mysvcd
```
You should see `mysvcd_t` in the process label.

---

## Uninstall the Module (if you ought to do in the future...)

Stop and disable the service and follow the steps below.

### 1. Reset file labels

#### For storage module

If you have assigned dedicated file labels (e.g., `mysvcd_var_log_t`, `mysvcd_var_cache_t`) to variable files ruled by `mysvcd_storage` module, you need to reset the labels to standard, before uninstall.

Example:
```bash
semanage fcontext -d "/var/log/mysvcd"
semanage fcontext -d "/var/log/mysvc(/.*)?"

restorecon -RFv /var/log/mysvcd
```

Confirm reset
```
ls -ldZ /var/log/mysvcd
ls -lZ /var/log/mysvcd
```

#### For main module

```bash
restorecon -Fv /opt/mysvc/bin/mysvcd
chcon -t bin_t /opt/mysvc/bin/mysvcd

semanage fcontext -d "/opt/mysvc/bin/mysvcd"
semanage fcontext -d "/opt/mysvc(/.*)?"

restorecon -RFv /opt/mysvc
```

Confirm reset
```bash
ls -ldZ /opt/mysvc
ls -lZ /opt/mysvc
```

### 2. Uninstall the policy modules

#### Storage module

```bash
semodule -v -X 300 -r mysvcd_storage
semodule -lfull | grep mysvcd_storage
```

#### Main module

```bash
semodule -v -X 300 -r mysvcd
semodule -lfull | grep mysvcd
```
