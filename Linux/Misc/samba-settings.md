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

- `-s /sbin/nologin`: disable shell logins (SSH etc.) – Samba access is still allowed.
- `-m -k /dev/null`: create an empty home directory without skeleton files.

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

**`/etc/samba/smb.conf`**
```ini
[global]
   # Restrict Samba to IPv4 addresses only (no IPv6)
   interfaces = 127.0.0.1 192.168.1.23
   bind interfaces only = yes
   # Listen TCP only; disable NBT (udp:139)
   server smb ports = 445

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

   # Unix group-based full access control
   valid users = @sambashare
   force group = sambashare

   create mask = 0664
   directory mask = 2775

   # IP based protection
   hosts allow = 127. 192.168.1.0/255.255.255.0
```

**`/etc/samba/user.map`**

The `username map` file allows mapping Windows usernames (SMB clients) to specific Unix users on the server. This is especially useful when the Windows client sends usernames that do not directly correspond to valid Unix accounts. By defining these mappings, we can ensure uniform security and prevent unauthorized or misconfigured access resulting from unexpected username collisions.  
  
⚠️**Warning:** Do not create the dummy Unix user "nonexunix" on the Samba server system. Mapping to a non-existent user ensures that unexpected names will be safely rejected by the server.  

```ini
# Unix_name = SMB_name1 SMB_name2 ..
# Map specific Windows usernames to a single Unix user. 
# Typically, adding a dedicated SMB user (e.g., "archmanager", if it exists) is sufficient.
# The leading "!" ensures that processing stops once a match is found.
!sambauser1 = admin administrator
# Map all other Windows usernames to a dummy, non-existent Unix user "nonexunix",
# to prevent unexpected mapping to existing Unix users.
nonexunix = *
```

After editing, always validate:

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
smbclient -L //server-hostname -U sambauser1
smbclient //server-hostname/archive -U sambauser1
```

**On Windows, connect to:**

```text
\\server-hostname\archive
```

using `sambauser1` as the username.
