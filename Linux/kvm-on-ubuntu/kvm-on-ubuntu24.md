# KVM on Ubuntu Linux 24.04 (and maybe 22.04)

## 🧭 1. Policy

* **Manage virtual machines with LVM logical volumes**
  - Fast snapshots and cloning
  - Easy backup and rebuild
* **Use bridged networking**
  - Guests can behave as members of the LAN

---

## 🔨 2. Host Initial Setup

### Required Packages

```bash
apt update
apt install qemu-kvm libvirt-daemon-system libvirt-clients \
                 bridge-utils virt-manager virtinst cloud-image-utils
```

* **virt-manager** → GUI management (VNC connection, snapshots)
* **cloud-image-utils** → Fast deployment of cloud images for small VM setups

### Check Ubuntu Pro + ESM

```bash
pro status
```

* Confirm that `esm-apps` / `esm-infra` are `enabled`

---

## ⛃ 3. LVM Configuration

### Create a volume group for experiments

We use free space on an SSD (NVMe) drive here.

```bash
# Example: /dev/nvme0n1p3 is already reserved for experiments
pvcreate /dev/nvme0n1p3
vgcreate vg_vm /dev/nvme0n1p3
```

### Example: Create a logical volume for a VM

```bash
# Create 20GB of disk space for "testvm"
lvcreate -L 20G -n testvm vg_vm
```

---

## 🖧 4. Network Configuration (Bridge)

### Disable `virbr0`

```bash
virsh net-autostart default --disable
virsh net-destroy default
```

### Delete or disable NetworkManager profiles

1. **Find the NetworkManager profile**:

   ```bash
   nmcli connection show
   ```

2. **Delete or disable it**:

   * Delete:

     ```bash
     nmcli connection delete "Ethernet1"
     ```
   * Or disable without deleting:

     ```bash
     nmcli connection modify "Ethernet1" connection.autoconnect no
     nmcli connection down "Ethernet1"
     mv /etc/netplan/90-NM-xxxxxxxx.yaml{,.disabled}
     # The file name 90-NM-xx..yaml is a YAML file generated from the NetworkManager configuration.
     # Read the file contents to determine the exact name.
     # You must also do the same for NM Wi-Fi connections if they exist.
     # Any YAML files with `renderer: NetworkManager` must not exist!
     ```
     > 💡 **Need to re-enable it?**
     > ```bash
     > mv /etc/netplan/90-NM-xxxxxxxx.yaml{.disabled,}
     > nmcli connection modify "Ethernet1" connection.autoconnect yes
     > nmcli connection up "Ethernet1"
     > ```
     > See also: [**How to switch between netplan and NetworkManager**](#how-to-switch-between-netplan-and-networkmanager)

3. **Disable and stop the NetworkManager service**:

     ```bash
     systemctl disable NetworkManager.service --now
     ```

### Create the netplan config for a bridge backed by Ethernet

* Static address, gateway, and DNS are configured on the bridge, **not** on the NIC.
* The physical interface (`enp3s0`) has no IP address assigned — it is only a bridge port.

> 📝 Most of the bunches of commands and definitions are found as files under [`net-br0`](net-br0) folder.

**Enable and start `systemd-networkd.service`**

```bash
systemctl enable systemd-networkd --now
```

**[`/etc/netplan/01-br0.yaml`](net-br0/netplan)**

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp3s0:
      dhcp4: no
      dhcp6: no
  bridges:
    br0:
      interfaces: [enp3s0]
      addresses:
        - 192.168.1.5/24
      routes:
        - to: default
          via: 192.168.1.252
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
```

**Apply the configuration**

```bash
netplan generate
netplan apply
  
ip addr show br0
bridge link
```

**Tune the physical network interface**

1. **[`/etc/udev/rules.d/99-tune-enp3s0.rule`](net-br0/udev)**

   ```bash
   ACTION=="add", SUBSYSTEM=="net", KERNEL=="enp3s0", RUN+="/usr/sbin/ethtool -K enp3s0 gro off gso off tso off"
   ACTION=="add", SUBSYSTEM=="net", KERNEL=="enp3s0", RUN+="/usr/sbin/ethtool -G enp3s0 rx 2048 tx 2048"
   ```

2. **Apply the rule**

   ```bash
   udevadm control --reload
   udevadm trigger --action=add
   ```
   or reboot.

**Update libvirt to use `br0`**

```bash
virsh net-define /dev/stdin <<EOF
<network>
  <name>br0-net</name>
  <forward mode="bridge"/>
  <bridge name="br0"/>
</network>
EOF

virsh net-list --all
virsh net-dumpxml br0-net
virsh net-autostart br0-net
virsh net-start br0-net
virsh net-info br0-net
```

---

#### How to switch between netplan and NetworkManager

**Switch to netplan bridge mode (Mode A): [`net-br.sh`](net-br0)**
```bash
nmcli connection modify "Ethernet1" connection.autoconnect no
nmcli connection down "Ethernet1" || true
mv /etc/netplan/90-NM-xxxxxxxx.yaml{,.disabled}
# The file name 90-NM-xx..yaml is a YAML file generated from the NetworkManager configuration.
# Read the file contents to determine the exact name.

mv /etc/netplan/01-br0.yaml.disabled /etc/netplan/01-br0.yaml
netplan generate
netplan apply
```

**Switch to NetworkManager mode (Mode B): [`net-nm.sh`](net-br0)**
```bash
mv /etc/netplan/01-br0.yaml /etc/netplan/01-br0.yaml.disabled
netplan generate
netplan apply

mv /etc/netplan/90-NM-xxxxxxxx.yaml{.disabled,}
nmcli connection modify "Ethernet1" connection.autoconnect yes
nmcli connection up "Ethernet1"
```

---

## 🖥️ 5. VM Creation Example

### Install directly from ISO

```bash
lvcreate -L 20G -n testvm vg_vm
virt-install \
  --name testvm \
  --memory 4096 \
  --vcpus 2 \
  --boot uefi \
  --disk path=/dev/vg_vm/testvm,bus=virtio \
  --cdrom /path/to/ubuntu-22.04.iso \
  --os-variant ubuntu22.04 \
  --network bridge=br0,model=virtio \
  --graphics spice
```
> 💡 **To make this reproducible, we can automate it with scripts.**
> See the sample scripts in the [`scripts`](scripts) folder.
> `virt-install-*.sh` files are the main scripts, while the other `*.sh` and `*.py` are helper libraries.

### Fast deployment from a cloud image

```bash
# Download the Ubuntu 22.04 cloud image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

# Deploy it onto LVM
qemu-img convert -f qcow2 -O raw jammy-server-cloudimg-amd64.img /dev/vg_vm/testvm
```

`cloud-init` makes it possible to log in immediately.

---

## ♻️ 6. Snapshot Management

### Backup, restore, remove

* Create a snapshot (backup)

  ```bash
  lvcreate -s -n testvm_snap -L 4G /dev/vg_vm/testvm
  ```

* Merge the snapshot (restore/revert)

  ```bash
  # Check whether the LVs are mounted
  findmnt -o SOURCE,TARGET /dev/vg_vm/testvm
  findmnt -o SOURCE,TARGET /dev/vg_vm/testvm_snap
  # If they are, stop the VM using them.

  # Deactivate the LVs
  lvchange --activate n vg_vm/testvm
  lvchange --activate n vg_vm/testvm_snap

  # Merge the snapshot
  lvconvert --merge testvm_snap

  # Activate the LV
  lvchange --activate y vg_vm/testvm
  ```

* Watch the snapshot LV usage %

  ```bash
  lvs -a -o +data_percent
  # Example output
  LV            VG       Attr       LSize   ... Data% 
  testvm_snap  vg_vm    owi-aos---  48.00g
  testvm_snap  vg_vm    swi-a-s---   4.00g      1.14
  ```

  If it grows too large, simply extend the snapshot LV. (Extending the snapshot LV does not disrupt the running VM or the snapshot itself.)

  ```bash
  lvextend -L +2G /dev/vg_vm/testvm_snap
  ```

* Remove a snapshot (forget)

  This simply discards the snapshot LV that has been storing journaled changes since it was created. No “delta disk integration back to the main disk” like vSphere happens in LVM, because the main LV remains active and writable even after the snapshot is removed.

  ```bash
  lvremove /dev/vg_vm/testvm_snap
  ```

### Clone into a separate VM

```bash
lvcreate -n testvm_clone -L 20G vg_vm
dd if=/dev/vg_vm/testvm of=/dev/vg_vm/testvm_clone bs=4M status=progress
# or, if the LV contains many unused blocks (zeros), you can save time with:
dd if=/dev/vg_vm/testvm of=/dev/vg_vm/testvm_clone bs=4M conv=sparse status=progress
```

---

## 🎯 7. Operational Best Practices

1. **Manage VMs by workload using snapshots**

   * If an experiment breaks the VM, roll back immediately
2. **Back up by dumping the LVM snapshot externally with `dd`**

   * If speed matters, recover with `lvconvert --merge`
3. **Use bridging by default; NAT can also be used for experiments**
4. **Store virtual disks directly on LVM**

   * Faster than qcow2, and SSD performance can be fully utilized

---
