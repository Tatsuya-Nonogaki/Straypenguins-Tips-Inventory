# SELinux Practical Tips & Modules

## Overview

This folder provides practical, scenario-driven guides for customizing, extending, and troubleshooting SELinux policy modules on modern Linux systems (with a focus on RHEL9/CentOS Stream 9 and derivatives).  
It includes step-by-step instructions, real-world examples, and reusable policy patterns for admins and developers managing their own services or customizing access for standard daemons.

---

## Table of Contents

- [Overview](#overview)
- [Environment and Conventions](#environment-and-conventions)
- [The Gist](#the-gist)
- [Documents](#documents)
- [Glossary](#glossary)

---

## Environment and Conventions

- **Platform:** RHEL9/CentOS Stream 9 (concepts and tools apply to most SELinux-enabled distros)
- **Conventions:**  
  - All paths, commands, and policy examples use standard Linux and SELinux tools.
  - Replace names like `mysvcd`, `httpd`, or custom port numbers as appropriate for your environment.

For terminology and SELinux-specific labels used in these documents, see the [Glossary](#glossary) section below.

---

## The Gist

**Allow httpd outbound access to a custom port (e.g., 7003):**
```bash
# Install SELinux tools
dnf install policycoreutils-devel selinux-policy-devel

# Search for denials
ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR | grep httpd

# If needed, create and load a custom port type and allow httpd to connect:
# (See detailed steps in [SELinux Policy Module for httpd on Port 7003](selinux-mod_wl-allow-httpd-7003.md))
```

**Create and load a custom policy module for your own service:**
```bash
# Write your .te file (see examples)
checkmodule -M -m -o mysvcd.mod mysvcd.te
semodule_package -o mysvcd.pp -m mysvcd.mod
semodule -v -X 300 -i mysvcd.pp
```

**Troubleshoot SELinux denials:**
```bash
# Search audit logs for denials
ausearch -m AVC,USER_AVC,SELINUX_ERR,USER_SELINUX_ERR -su mysvcd_t

# Check active policy
sesearch --allow -s mysvcd_t
```

For more detailed how-to, see the Documents section below.

---

## Documents

- **[Manage SELinux to Allow httpd to Access Port 7003/TCP](selinux-mod_wl-allow-httpd-7003.md):**  
  How to allow httpd outbound access to a non-standard port using SELinux, with both quick and organized policy methods.

- **[Create SELinux Policy Module for Your Own Service](selinux-create-own-service-policy.md):**  
  Step-by-step guidance for designing, building, labeling, and uninstalling custom SELinux policy modules for your own programs and data.

- **[SELinux Policy Troubleshooting: Resolving Audit Denials for a Custom Service](selinux-service-policy-troubleshooting.md):**  
  How to diagnose, interpret, and resolve SELinux denials—including audit log search, policy verification, and best practices for incremental policy updates.

---

## Glossary

### Basic Concepts
- **SELinux**  
  Security-Enhanced Linux, a kernel security module providing mandatory access controls.

- **Label**  
  The SELinux security context assigned to an object (such as a file, process, or port). It is composed of four fields: user, role, type (or domain), and level. The full label is also called `scontext`, e.g., `system_u:system_r:httpd_t:s0`.

### Policy Structure & Logic
- **Policy Module**  
  User-defined extension to SELinux policy, typically loaded via `semodule` and built from various source files.

- **Domain / Type**  
  SELinux label assigned to a process (e.g., `httpd_t`, `mysvcd_t`); controls process permissions.

- **Role**  
   Used primarily in Role-Based Access Control (RBAC) to define what domains (types) a user or process can enter. Commonly used for user logins and confined user domains, but also plays an important role in Domain Transition.

- **File Type**  
  SELinux label for files/directories (e.g., `mysvcd_exec_t`, `mysvcd_var_t`).

- **Port Type**  
  SELinux label that controls access to a port or port range (e.g., `http_port_t`, `httpd_wls_port_t`).

- **Class**  
  SELinux object class, describing the kind of object (e.g., `file`, `dir`, `tcp_socket`).

- **Level**  
  The sensitivity level and (optionally) categories of an SELinux context, represented as the last field (e.g., `s0`, `s0-s0:c0.c1023`). Levels are mainly used in Multi-Level Security (MLS) or Multi-Category Security (MCS) policies to provide finer-grained labeling and access control.

- **Domain Transition**  
  An SELinux mechanism where a process changes its domain (type), usually by executing a file with a different type. This controls how processes switch domains, such as when a service is started by a process manager (e.g., systemd).

- **Permission / Operation**  
  Specific action on a class (e.g., `connect`, `read`, `write`, `getopt`).

- **AVC**  
  Access Vector Cache; SELinux component that logs access decisions and denials. It is typically observed in audit logs and queried with the `sesearch` tool.

### Policy File Types
- **`.te` file**  
  Type Enforcement source file, defining types, permissions, and rules for a policy module.

- **`.mod` file**  
  Compiled intermediate module file, created from a `.te` file by `checkmodule`.

- **`.if` file**  
  Interface file, defines reusable policy interfaces for modules.

- **`.pp` file**  
  Policy Package file, the final compiled policy module loaded into SELinux by `semodule`.

### Tools
- **`checkmodule`**  
  Tool to compile a `.te` source file into a binary `.mod` module file.

- **`semodule_package`**  
  Tool to bundle a `.mod` file (and optionally `.fc` and `.if` files) into a `.pp` policy package for installation.

- **`semodule`**  
  Tool to manage (install, remove, or list) SELinux policy modules.

- **`semanage`**  
  Tool to define, modify, or delete SELinux configuration such as port, file context, and boolean mappings.

- **`restorecon`**  
  Command to relabel files/directories according to the current SELinux policy. SELinux labels are stored as extended attributes within the filesystem, not in a separate central database.

- **`setenforce`**  
  Command to change the SELinux mode between enforcing and permissive.

- **`getenforce`**  
  Command to display the current SELinux mode (Enforcing, Permissive, or Disabled).

- **`ausearch`**  
  Tool to search audit logs for SELinux (AVC) denials and events.

- **`sesearch`**  
  Tool to search SELinux policy rules for permissions and access vectors.
