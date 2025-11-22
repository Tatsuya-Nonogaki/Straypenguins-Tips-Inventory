# Multi-User Support Feature

## Overview

The `cloudinit-linux-vm-deploy.ps1` script now supports defining multiple users in the parameter file using `user1`, `user2`, `user3`, etc. keys. This allows you to configure multiple OS users with their own SSH keys while maintaining backward compatibility with existing single-user configurations.

## Key Features

1. **Multiple User Definitions**: Define users as `user1`, `user2`, ... with individual SSH keys
2. **Primary User Selection**: Designate one user as "primary" for in-guest operations (VMware Tools commands)
3. **Per-User SSH Keys**: Use `{{userN.SSH_KEYS}}` placeholders in templates for each user's SSH keys
4. **Backward Compatible**: Existing parameter files continue to work without modification

## Usage

### Parameter File Configuration

Define multiple users in your `vm-settings_*.yaml` file:

```yaml
# Multi-user configuration
user1:
  name: admin01
  primary: true  # This user is selected for in-guest VMware Tools operations
  password: "AdminPass123!"
  password_hash: "$6$rounds=656000$..."
  user_groups: "wheel,adm,systemd-journal"
  ssh_keys:
    - "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA... admin01@workstation"
    - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... admin01@laptop"

user2:
  name: deploy01
  password: "DeployPass456!"
  password_hash: "$6$rounds=656000$..."
  user_groups: "wheel"
  ssh_keys:
    - "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... deploy01@ci-server"

user3:
  name: monitor01
  password: "MonitorPass789!"
  password_hash: "$6$rounds=656000$..."
  user_groups: "systemd-journal"
  ssh_keys:
    - "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... monitor01@monitoring"
```

### Template Configuration

Use per-user placeholders in your `user-data_template.yaml`:

```yaml
#cloud-config
hostname: {{hostname}}

users:
  - name: {{user1.name}}
    groups: {{user1.user_groups}}
    lock_passwd: false
    passwd: {{user1.password_hash}}
    ssh_authorized_keys:
{{user1.SSH_KEYS}}
    shell: /bin/bash

  - name: {{user2.name}}
    groups: {{user2.user_groups}}
    lock_passwd: false
    passwd: {{user2.password_hash}}
    ssh_authorized_keys:
{{user2.SSH_KEYS}}
    shell: /bin/bash
```

## How It Works

### 1. Primary User Selection

During script initialization (after loading the parameter file):

- The script searches for all `userN` keys in the parameter file
- It selects the first user with `primary: true`
- If no user has `primary: true`, it selects the first user (user1)
- The selected user's `name` and `password` are copied to `$params.username` and `$params.password`
- This ensures in-guest operations (Phase 2, 3, 4) use the correct credentials

### 2. SSH Keys Placeholder Replacement

During Phase 3 (cloud-init seed generation):

- For each `userN` in the parameter file, the script processes `{{userN.SSH_KEYS}}` placeholders
- SSH keys are formatted with proper YAML indentation (6 spaces)
- Empty SSH key arrays are rendered as `[]` to maintain valid YAML
- The original `{{SSH_KEYS}}` placeholder (for backward compatibility) is still supported

### 3. Replace-Placeholders Function

The existing `Replace-Placeholders` function continues to work:

- It recursively replaces `{{userN.field}}` placeholders (e.g., `{{user1.name}}`, `{{user2.password_hash}}`)
- SSH_KEYS is handled separately due to special formatting requirements
- All other fields work with the standard replacement logic

## Examples

### Example 1: Multi-User Configuration

See `params/vm-settings_multiuser_example.yaml` and `templates/original/user-data_multiuser_template.yaml` for a complete example.

### Example 2: Backward Compatible (Single User)

Existing configurations continue to work:

```yaml
username: mainte
password: "naks9slewiv"
password_hash: "$6$Kc8......"
user_groups: "wheel,adm,systemd-journal"
ssh_keys:
  - "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEAr..."
```

Template:
```yaml
users:
  - name: {{username}}
    groups: {{user_groups}}
    passwd: {{password_hash}}
    ssh_authorized_keys:
{{SSH_KEYS}}
```

## Technical Details

### Code Modifications

1. **Primary User Mapping** (lines 498-530 in `cloudinit-linux-vm-deploy.ps1`)
   - Executes immediately after parameter file loading
   - Identifies all `userN` keys and sorts them numerically
   - Selects primary user based on `primary` flag or defaults to first user
   - Maps `name` and `password` to legacy fields for VMware Tools operations

2. **Per-User SSH_KEYS Replacement** (lines 1148-1172 in `cloudinit-linux-vm-deploy.ps1`)
   - Executes during Phase 3, inside the `foreach ($f in $seedFiles)` loop
   - Processes after the standard `{{SSH_KEYS}}` placeholder replacement
   - Uses the same indentation and formatting as the original SSH_KEYS logic
   - Supports empty arrays with explicit `[]` notation

### Indentation

SSH keys are indented with **6 spaces** to match the cloud-init YAML structure:

```yaml
    ssh_authorized_keys:
      - "ssh-rsa AAAA..."  # 6 spaces before the dash
      - "ssh-ed25519 ..."
```

### Empty SSH Keys

When a user has no SSH keys (`ssh_keys: []` or no `ssh_keys` key), the placeholder is replaced with:

```yaml
    ssh_authorized_keys:
      []
```

This maintains valid YAML syntax and avoids commented-out items.

## Testing

Run the test script to verify the logic:

```bash
pwsh /tmp/test-multiuser-logic.ps1
```

The test validates:
- Primary user selection with and without the `primary` flag
- SSH_KEYS placeholder replacement for multiple users
- Handling of empty SSH key arrays

## Backward Compatibility

The implementation is fully backward compatible:

- **Existing parameter files**: Continue to work without modification
- **Existing templates**: The `{{SSH_KEYS}}` placeholder still works
- **Replace-Placeholders function**: Unchanged interface and behavior
- **In-guest operations**: Continue to use `$params.username` and `$params.password`

## Migration Guide

To migrate from single-user to multi-user configuration:

1. **Update parameter file**:
   ```yaml
   # Old format
   username: mainte
   password: "pass123"
   ssh_keys:
     - "ssh-rsa ..."

   # New format
   user1:
     name: mainte
     primary: true
     password: "pass123"
     ssh_keys:
       - "ssh-rsa ..."
   ```

2. **Update template** (optional):
   ```yaml
   # Old placeholder
   {{SSH_KEYS}}

   # New placeholder
   {{user1.SSH_KEYS}}
   ```

3. **Test**: Run the script with `-Phase 3` only to verify cloud-init seed generation without deploying a VM.

## Limitations

- User keys must follow the pattern `user1`, `user2`, `user3`, etc. (numeric suffix)
- The `primary` flag is evaluated as a truthy value (relies on PowerShell-YAML parsing)
- SSH keys must be provided as YAML arrays/sequences
- Array keys (as opposed to hash keys) are not supported in `Replace-Placeholders`

## Support

For issues or questions, refer to the main script documentation or create an issue in the repository.
