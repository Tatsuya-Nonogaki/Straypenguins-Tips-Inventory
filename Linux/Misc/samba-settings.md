## Configure Samba Server on RHEL9

### 📥 1. Install packages
```bash
dnf install samba samba-client
```
This installs dependencies such like `samba-common`, `samba-common-tools` (`testparm` etc.).

---

### 👤 2. Create OS Users

**1. Create shared group**
```bash
groupadd -g 1990 sambashare
```

**2. Create user**
```bash
useradd -u 1991 -m -k /dev/null -s /sbin/nologin sambauser1
usermod -aG sambashare sambauser1
echo "Qwerty123" | passwd --stdin sambauser1
```

This creates `sambauser1` as the primary Samba user.

- `-s /sbin/nologin`: disable shell logins (SSH etc.) – Samba access is still allowed.
- `-m -k /dev/null`: create an empty home directory without skeleton files.

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
mkdir -p /data/archive
chown root:sambashare /data/archive
# Set SGID bit so group is inherited to newly added sub-components.
chmod 2775 /data/archive
```

- Group ownership is `sambashare`.
- `2775` (SGID) ensures new files/dirs inherit the `sambashare` group.

**Set SELinux label**
```bash
# Define the context label (once is enough)
semanage fcontext -a -t samba_share_t "/data/archive(/.*)?"
# Label it
restorecon -FRv /data/archive
ls -lZa /data/archive
```

📝`semanage` is provided by `policycoreutils-python-utils` if not installed.

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

[archive]
   comment = archive on Rocky 9
   path = /data/archive
   browseable = yes
   writable = yes

   # Unix group-based access control:
   # If you prefer to grant access per user (instead of by group as below),
   # replace the right-hand side with a list of Unix users.
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
📌 Do NOT give it an empty or simple password; use [pw-o-matic](https://github.com/Tatsuya-Nonogaki/pw-o-matic) on our Repository or `openssl rand -base64 32`, for example.

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
journalctl -u smb
```

**Check from a client (example from Linux):**

```bash
smbclient -L //server_hostname -U admin
smbclient //server_hostname/archive -U admin
```

**On Windows, connect to:**

```text
\\server_hostname\archive
```

using `administrator` (or `admin`) as the username, which is internally mapped to the Unix account `sambauser1` via `user.map`.
