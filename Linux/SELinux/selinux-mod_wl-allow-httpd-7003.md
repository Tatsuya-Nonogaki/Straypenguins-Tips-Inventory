# Manage SELinux to Allow httpd to Access Port 7003 (or Else)/TCP
**Also refers to the case where the service is your own, not `httpd`.  
This document provides practical, adaptable steps for customizing SELinux policy to securely enable network and file access for any system service.**

---

## Install Prerequisite Packages (RHEL9)

```bash
dnf install policycoreutils-devel selinux-policy-devel
# Optional:
dnf install setools-console
```

---

## See What Is Going On

Search SELinux denials for a specific process name. Use the exact name of the executable with `-c` (`--comm`)—no partial match:

```bash
ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR -c httpd
```

Example output:

> type=AVC msg=audit(1752813896.450:64983): avc:  denied  { name_connect } for  pid=2766333 comm="httpd" dest=7003 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:unreserved_port_t:s0 tclass=tcp_socket permissive=0

If you want to find denials for any command starting with `http`, omit `-c` and filter with `grep`:

```bash
ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR | grep 'comm="http'
```

---

## Customize the Policy —Automatic Way (Moderate Security - All `unreserved_ports` Are Allowed from httpd)

> **Caution:**  
> When filtering audit logs for use with `audit2allow`, be aware that narrowing results with the `-m` option (e.g., `-m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR`) may accidentally exclude relevant SELinux denial messages, especially if your system logs additional or unexpected types.  
> For best results, omit the `-m` option when piping `ausearch` output to `audit2allow`; the tool will automatically ignore unrelated messages and process all necessary SELinux denials.

### Preview the Resultant Rule

```bash
ausearch -c httpd | audit2allow -R
```

### Auto-Generate .te Module

```bash
ausearch -c httpd --raw | audit2allow -M myhttpd_mod_wl
```

Then continue to [SE Module Build and Install (Common)](#se-module-build-and-install-common)

---

## Customize the Policy —Organized Way (More Secure)

### Check if Port 7003 is Assigned

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

### ⚠️ Safety Check Before Deleting Port Assignment

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
    ss -tnlp | grep ':7003'
    # Find the PID, then check its SELinux context:
    ps -Z -p <pid>
    # Make sure the running process is not using a domain that needs this port type
    ```

### Delete Existing Assignment _If Safe to Do_

If you have confirmed the port is not in use:

```bash
semanage port -d -p tcp 7003
```

**Otherwise, reuse the predefined label.**

---

### Tips: Expand Port Ranges

```bash
semanage port -l | awk '$1=="afs3_callback_port_t" && $2=="tcp" {$1=$2=""; print $0}' | \
  tr ',' '\n' | while read p; do
    if [[ "$p" == *-* ]]; then seq ${p%-*} ${p#*-}; else echo $p; fi
done
```

---

### Prepare Module Directory

```bash
mkdir -p myhttpd_mod_wl
cd myhttpd_mod_wl
```

### Create a Port Type Module

#### File: `myhttpd_wls_type.te`

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

#### Build and Install Port-Type Module

```bash
checkmodule -M -m -o myhttpd_wls_type.mod myhttpd_wls_type.te
semodule_package -o myhttpd_wls_type.pp -m myhttpd_wls_type.mod
semodule -i myhttpd_wls_type.pp
semodule -lfull | grep myhttpd_wls_type
```

### Create a Domain Type Module for Your Custom Executable here, if the Domain Type is your own `mysvcd_t` instead of predefined `httpd_t`

#### 1. Define Exec Type and Domain Type, with Transition for systemd

**File: `mysvcd.te`**
```te
module mysvcd 1.0;

require {
    type systemd_t;
    type mysvcd_t;
    type mysvcd_exec_t;
    type mysvcd_opt_t;
    type httpd_wls_port_t;
    class tcp_socket name_connect;
    class process transition;
    class file { execute read open write append create unlink };
    class dir { read search write add_name remove_name };
}

# Define the domain type for your daemon
type mysvcd_t;

# Define the exec type for your binary
type mysvcd_exec_t;
files_type(mysvcd_exec_t)

# Define the type for your package directory
type mysvcd_opt_t;
files_type(mysvcd_opt_t)

# Allow systemd to read/open/execute your binary
allow systemd_t mysvcd_exec_t:file { read open execute };

# Transition: When systemd_t executes mysvcd_exec_t, the process transitions to mysvcd_t
type_transition systemd_t mysvcd_exec_t:process mysvcd_t;

# Allow your service domain to connect to the custom port type
allow mysvcd_t httpd_wls_port_t:tcp_socket name_connect;

# Allow mysvcd_t to manage files in its own installed directory
allow mysvcd_t mysvcd_opt_t:dir { read search write add_name remove_name };
allow mysvcd_t mysvcd_opt_t:file { read write append open create unlink };
```

#### 2. Build and Install Domain Module

```bash
checkmodule -M -m -o mysvcd.mod mysvcd.te
semodule_package -o mysvcd.pp -m mysvcd.mod
semodule -i mysvcd.pp
semodule -lfull | grep mysvcd
```

#### 3. Label Your Binary and Package Directory

```bash
semanage fcontext -a -t mysvcd_exec_t "/opt/mypkg/mysvcd"
restorecon -Fv /opt/mypkg/mysvcd

semanage fcontext -a -t mysvcd_opt_t "/opt/mypkg(/.*)?"
restorecon -FRv /opt/mypkg/
```

---

#### Additional note on other directory to allow your own binary to R/W

If your service needs to read/write other directories—such as `/var/log/mypkg/`, `/var/cache/mypkg/`, `/var/lib/mypkg/`, or `/var/tmp/mypkg/`—it is best practice to manage these in a separate TE module for modularity and future flexibility.

> In this example, we define a _catch-all_ type `mysvcd_var_t`. If your service requires more strict separation of log, cache, lib, etc., you can easily split into more granular types (e.g., `mysvcd_var_log_t`, `mysvcd_var_cache_t`, etc.).

**Example TE policy for variable data directory: `mysvcd_storage.te`:**

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

Furthermore, if the file type your program accesses is a predefined one, the `te` file will look like below:

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

**Build and install the module:**

```bash
checkmodule -M -m -o mysvcd_storage.mod mysvcd_storage.te
semodule_package -o mysvcd_storage.pp -m mysvcd_storage.mod
semodule -i mysvcd_storage.pp
semodule -lfull | grep mysvcd_storage
```

**Example labeling and restorecon commands:**

```bash
semanage fcontext -a -t mysvcd_var_t "/var/log/mypkg(/.*)?"
semanage fcontext -a -t mysvcd_var_t "/var/cache/mypkg(/.*)?"
semanage fcontext -a -t mysvcd_var_t "/var/lib/mypkg(/.*)?"
restorecon -FRv /var/log/mypkg/ /var/cache/mypkg/ /var/lib/mypkg/
```

**You can build, install, and update these modules independently as your package requirements evolve.**

---

### Create the Main Module

#### File: `myhttpd_mod_wl.te` (Simple)

```te
module myhttpd_mod_wl 1.0;

require {
    type httpd_t;
    type httpd_wls_port_t;
    class tcp_socket name_connect;
}

allow httpd_t httpd_wls_port_t:tcp_socket name_connect;
```

Or..

#### File: `myhttpd_mod_wl.te` (Includes Predefined Label)

```te
module myhttpd_mod_wl 1.0;

require {
    type httpd_t;
    type httpd_wls_port_t;
    type afs3_callback_port_t;
    class tcp_socket name_connect;
}

allow httpd_t httpd_wls_port_t:tcp_socket name_connect;
allow httpd_t afs3_callback_port_t:tcp_socket name_connect;
```

#### Or.. if the Domain Type is your own `mysvcd_t`, File: `myhttpd_mod_wl.te` is like this
> Using the same module name though it should be e.g., `mysvcd_mod_wl` in this case, to simplify the subsequent explanation.

```te
module myhttpd_mod_wl 1.0;

require {
    type mysvcd_t;
    type httpd_wls_port_t;
    class tcp_socket name_connect;
}

allow mysvcd_t httpd_wls_port_t:tcp_socket name_connect;
```

---

## SE Module Build and Install (Common)

```bash
checkmodule -M -m -o myhttpd_mod_wl.mod myhttpd_mod_wl.te
semodule_package -o myhttpd_mod_wl.pp -m myhttpd_mod_wl.mod
semodule -i myhttpd_mod_wl.pp

# Verify installation
semodule -lfull | grep myhttpd_mod_wl
ls -l /var/lib/selinux/targeted/active/modules/*/myhttpd_mod_wl

# Check actual permission rule
sesearch --allow -s httpd_t -t httpd_wls_port_t -c tcp_socket -p name_connect
# (If using automatic audit2allow)
sesearch --allow -s httpd_t -t unreserved_port_t -c tcp_socket -p name_connect
```

---

## Port Assignment (for Manual Build)

```bash
semanage port -a -t httpd_wls_port_t -p tcp 7003
semanage port -a -t httpd_wls_port_t -p tcp 7005
```

**Verify Assignment**

```bash
echo $(semanage port -l | awk '$1=="httpd_wls_port_t" && $2=="tcp" {$1=$2=""; print $0}')
```

---

## Start and Verify with systemd (in the case of your own domain type `mysvcd_t`)

Start your service via systemd, and check the running process label:

```bash
systemctl start mysvcd.service
ps -Z -C mysvcd
```
You should see `mysvcd_t` in the process label.

---

## Uninstall the Module (if you ought to do in the future...)

```bash
semodule -r myhttpd_mod_wl
semodule -lfull | grep myhttpd_mod_wl
```
