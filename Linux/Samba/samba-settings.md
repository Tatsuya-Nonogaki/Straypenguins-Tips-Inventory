## Configure Samba Server on RHEL9

This guide provides a practical, security‑conscious setup for Samba on RHEL9. It streamlines installation; user and account design, including username mapping (e.g., mapping admin/administrator to the primary Unix account); share configuration (permissions and SELinux); logging and rotation; and network hardening—such as disabling legacy NetBIOS/NBT (UDP/139) listening and enforcing strict IP‑based whitelist access controls.

> 💡 **Related script: `samba-provision.sh`**  
> This document is a *quick-start style* explanation that focuses on the overall design, including `smb.conf` and `user.map` examples.  
> For the actual provisioning steps—creating Unix and Samba users, setting passwords, preparing the shared directory, and applying SELinux labels—see the companion script **[samba-provision.sh](samba-provision.sh)**, which implements these ideas in a reproducible, step-by-step procedure.
>  
> If you prefer not to perform user creation, shared directory filesystem permission setting and SELinux labeling (steps **2 to 4** below) manually, run the provisioning script `samba-provision.sh` as root. It will:
> - Create the primary Unix/Samba user for access
> - Create the dummy Unix/Samba user (`nonexunix`) for catching undefined SMB usernames used in `user.map`
> - Prepare the shared directory (permissions and SGID)
> - Apply consistent SELinux labels, including careful treatment of custom mount points and `lost+found`

---

### 📥 1. Install packages
```bash
dnf install samba samba-client
```
This installs dependencies such like `samba-common`, `samba-common-tools` (`testparm` etc.).

---

### 👤 2. Create OS Users

> **Password design note**  
> For better separation of concerns, it is recommended to treat the Unix account password and the Samba (SMB) password independently:
> - The Unix account used for Samba access (e.g. `sambauser1`) does **not** need a valid shell password; you can lock or delete the Unix password and let only the Samba passdb (`pdbedit`) control SMB logins.
> - If you do set a Unix password, make it **different from** the Samba password and sufficiently long and complex.
>  
> The companion script **[samba-provision.sh](samba-provision.sh)** demonstrates both approaches:
> it can either lock the Unix account password or set a hard-to-type one, depending on a configuration variable.

**1. Create shared group**
```bash
groupadd -g 1990 sambashare
```

**2. Create user**
```bash
useradd -u 1991 -m -k /dev/null -s /sbin/nologin sambauser1
usermod -aG sambashare sambauser1
# Ensure the shadow password field is empty, then lock the account
passwd -d sambauser1
passwd -l sambauser1
```

This creates `sambauser1` as the primary Samba user.

- `-s /sbin/nologin`: disable shell logins (SSH etc.) – Samba access is still allowed.
- `-m -k /dev/null`: create an empty home directory without skeleton files.
- `passwd -d`: delete any existing password hash from the shadow entry.
- `passwd -l`: lock the account so that Unix logins are not possible.

Alternatively, you can choose to set a long, complex random password instead of locking the Unix account, for example:

```bash
echo "3ovtajNowlIrm=gledsIsUd6" | passwd --stdin sambauser1
```

In both cases, the Samba password (managed via `pdbedit` in the next step) is independent from the Unix password and should be treated separately.

📝 **Note:** Later, we will also create a dummy Unix user to catch all *undefined* SMB usernames in order to secure Samba. See the [/etc/samba/user.map](#etcsambausermap) section under ["5. Configure Samba Server"](#%EF%B8%8F-5-configure-samba-server) for details.

---

### 📚 3. Register user to SAM DB

```bash
pdbedit -a sambauser1
pdbedit -Lv sambauser1
```

This registers the user into Samba’s `tdbsam` passdb backend and shows the detailed entry (including SIDs).

---

### 📁 4. Create shared directory

```bash
mkdir -p /data/sharedstore
chown root:sambashare /data/sharedstore
# Set SGID bit so group is inherited to newly added sub-components.
chmod 2775 /data/sharedstore
```

- Group ownership is `sambashare`.
- `2775` (SGID) ensures new files/dirs inherit the `sambashare` group.

**Set SELinux label**
```bash
# Define the context label (once is enough)
semanage fcontext -a -t samba_share_t "/data/sharedstore(/.*)?"
# Label it
restorecon -FRv /data/sharedstore
ls -lZa /data/sharedstore
```

📝`semanage` is provided by `policycoreutils-python-utils` if not installed.

> ⚠️ **SELinux and custom mount points**  
> When the share resides on a separate filesystem mounted at a non-standard path (e.g. `/data`, `/arch`), the mount point may initially be labeled `unlabeled_t`. Samba (`smbd_t`) cannot traverse paths that contain `unlabeled_t` in the directory chain (having `default_t` is not a problem).  
> In such cases:
> - First, fix the mount point label with `restorecon` so that it becomes a normal type (e.g. `default_t`).
> - Then apply a persistent `fcontext` rule for the share (or, on a fully dedicated volume, for the whole mount point), and run `restorecon` again.
> - If you label the entire mount point for Samba, pay special attention to the `lost+found` directory: it should keep the SELinux type `lost_found_t` (file class: directory), not `samba_share_t`.  
>  
> These conditions and the concrete ordering of operations (such as when to check for `unlabeled_t` and how to treat a dedicated Samba volume) are automated in the [samba-provision.sh](samba-provision.sh) script. Reading that script alongside this document will help clarify the exact decision points and procedures.

---

### ⚙️ 5. Configure Samba Server

#### /etc/samba/smb.conf
```ini
[global]
   # Restrict Samba to IPv4 addresses only (no IPv6)
   interfaces = 127.0.0.1 192.168.1.23
   bind interfaces only = yes
   # Listen TCP only; disable NBT (udp:139)
   smb ports = 445
   disable netbios = yes

   workgroup = WORKGROUP
   server string = Samba Server on Rocky 9
   security = user

   dos charset = CP932
   unix charset = UTF-8

   # Single log file, rotation is handled by logrotate(8)
   log file = /var/log/samba/smb.log
   # max log size = 0     ; Samba built-in rotation disabled (default)
   log level = 1
   # log level = 1 auth:3 ; alternative example: raise auth component only

   # Not using printer / home share features
   load printers = no
   printing = bsd
   printcap name = /dev/null
   disable spoolss = yes

   # Workgroup browser election preference; uncomment and tune only if needed
   # local master = yes
   # preferred master = yes
   # os level = 20

   # Hardened security
   username map = /etc/samba/user.map
   # Deny all login attempts with invalid credentials (rejects instead of mapping to guest)
   map to guest = Never

[sharedstore]
   comment = sharedstore on Rocky 9
   path = /data/sharedstore
   browseable = yes
   writable = yes

   # Unix group-based access control:
   # This configuration assumes that all Unix users referenced on the left side of
   # user.map (e.g. !sambauserX = ...) belong to the "sambashare" group, so
   # granting access by this group is sufficient ("valid users" does not define
   # the file operation owner).
   # Even if username-map is defined as 1:1 per user (e.g. sambauser1 = sambauser1, ...),
   # "valid users" does not need to enumerate each user explicitly in this strategy.
   valid users = @sambashare
   force group = sambashare

   create mask = 0664
   directory mask = 2775

   # IP-based protection: explicitly define "hosts deny" to avoid any ambiguity
   # in Samba's implementation and ensure a strict whitelist
   hosts allow = 127. 192.168.1.0/255.255.255.0
   hosts deny  = 0.0.0.0/0
```

#### /etc/samba/user.map

The `username map` file allows mapping Windows usernames (SMB clients) to specific Unix users on the server. This is especially useful when Windows clients send usernames that do not directly correspond to valid Unix accounts. By defining these mappings, you can enforce consistent security behavior and prevent unauthorized or misconfigured access caused by unexpected username collisions.  

The _JAIL_ user defined by `nonexunix = *` turns this into an effective whitelist:  
all SMB usernames that should have access **must be listed explicitly before** that catch‑all rule.

```ini
# Unix_name = SMB_name1 SMB_name2 ...
# Map specific Windows usernames to a single Unix user.
# Typically, mapping a dedicated SMB username (e.g. "archmanager") to a single
# representative Unix user ("sambauser1" in this example) is sufficient.
# If you want to handle each user separately, add explicit mappings for all of them,
# such as:  !sambauser2 = sambauser2
# The leading "!" ensures that processing stops once a match is found.
!sambauser1 = admin administrator

# Map all other Windows usernames to the non-loginable but existing Unix user "nonexunix"
# to discard them; this also prevents unexpected mapping to effective Unix users.
nonexunix = *
```

✅ The Unix username specified on the left-hand side in `user.map` must always exist as a Unix account on the server, otherwise, Samba will fail to start. When you define a dummy account (such as `nonexunix` in this example), ensure it exists on the server system but is non-loginable. Create it with the following command:

```bash
useradd --system -s /sbin/nologin nonexunix
```

Then, as an additional safeguard, also create a corresponding Samba account with the same name. This prevents Samba from even probing the dummy Unix account.  
📌 Do NOT give it an empty or simple password; use [pw-o-matic](https://github.com/Tatsuya-Nonogaki/pw-o-matic) or `openssl rand -base64 32`, for example. The provisioning script [samba-provision.sh](samba-provision.sh) follows exactly this pattern: it creates a non-loginable Unix account `nonexunix`, registers a Samba account of the same name with a long random password, and immediately disables it via `pdbedit -c '[D]'`.

```bash
# Register a Samba user of the exact name
pdbedit -a -u nonexunix
# Enter a long and complex password string:
new password: Uk%QuajmoHynejyiavojnaQuapByarz2
retype new password: Uk%QuajmoHynejyiavojnaQuapByarz2
# Set "disabled" flag to prevent any login attempts
pdbedit -r -u nonexunix -c '[D]'
# Review the properties
pdbedit -L -v -u nonexunix
```

> 📝 **Note:**  
> If you ever decide to enable guest mapping in `smb.conf` (for example, by using `map to guest = Bad User`), consider setting `guest account = nonexunix` so that any guest access is bound to this dedicated dummy account instead of the system-wide `nobody` user.

**After editing, always validate:**  
Note that `testparm` only validates the syntax of `smb.conf` and does not validate user existence or `user.map` semantics.

```bash
testparm
```

---

### 🔄 6. Tweak default 'logrotate.d/samba'

Samba package installs **`/etc/logrotate.d/samba`**.  

📝**Note:** RHEL9 default global rotation settings in `/etc/logrotate.conf` typically include `weekly`, `rotate 8`, `compress`, `dateext`.  

**Default:**
```ini
/var/log/samba/*log* {
    compress
    dateext
    maxage 365
    rotate 99
    notifempty
    olddir /var/log/samba/old
    missingok
    copytruncate
}
```

**Example tuned settings:**
```ini
/var/log/samba/*log* {
    # daily              ; consider 'daily' if required
    compress
    dateext
    maxage 90
    rotate 12
    notifempty
    olddir /var/log/samba/old
    missingok
    copytruncate
}
```

- `weekly` × `rotate 12` keeps approx. 3 months of logs.
- `maxage 90` removes logs older than 90 days.
- In environments with high log volume, consider `daily` with an adjusted `rotate` value.

---

### ⚡ 7. Enable Samba Server

```bash
systemctl enable --now smb
systemctl status smb
less /var/log/samba/smb.log
```

**Check from a client (example from Linux):**

```bash
smbclient -L //server_hostname -U admin
smbclient //server_hostname/sharedstore -U admin
```

**On Windows, connect to:**

```text
\\server_hostname\sharedstore
```

using `administrator` (or `admin`) as the username, which is internally mapped to the Unix account `sambauser1` via [user.map](#etcsambausermap).
