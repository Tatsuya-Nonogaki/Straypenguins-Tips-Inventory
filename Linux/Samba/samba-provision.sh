#!/bin/bash
#------------------------------------------------------------------------------
# samba-provision.sh
#
# Purpose:
#   Provision a minimal but security-conscious Samba environment on RHEL9
#   (and compatible) systems. This script automates:
#     - Creation of a primary Unix user and group for Samba access
#     - Optional locking or hardening of the Unix account password
#     - Creation of a dummy Unix/Samba user to catch all undefined SMB usernames
#       (used in conjunction with /etc/samba/user.map)
#     - Creation of the shared directory and its Unix permissions (SGID, group)
#     - SELinux labeling of the share (and optionally the whole volume),
#       including careful handling of mount-point unlabeled_t and lost+found
#
# Relationship to samba-settings.md:
#   - samba-settings.md is a quick-start style document that describes
#     the overall Samba configuration, including smb.conf and user.map examples.
#   - This script focuses on the *provisioning* aspects (users, passwords,
#     directory, and SELinux labels) and implements the design choices described
#     in the document, in a reproducible way.
#
# Usage:
#   - Review and adjust the variables at the beginning of each section in this
#     script (e.g. ALLOWUSER, SHAREDDIR, VOLUME_IS_SMB_DEDICATED, passwords).
#   - Run this script as root before finalizing /etc/samba/smb.conf and
#     /etc/samba/user.map.
#------------------------------------------------------------------------------
set -eu
trap '
 rc=$?
 func=${FUNCNAME[1]:-main}
 echo "ERROR (exit $rc) in ${BASH_SOURCE[1]}:${LINENO} [$func]: $BASH_COMMAND" >&2
 exit $rc
' ERR

# --- Create users to allow access ---
ALLOWUSER="sambauser1"
ALLOWGROUP="sambashare"
ALLOWSMBPWD="MyPassw0rd#%+/:=?@_"
# Optional: Unix user password
# If set, it must be different from Samba password and should be long and complex.
# If unset or empty, the Unix account will be locked instead.
ALLOWUNIXPWD=""

# Create an OS account
echo "***Creating Unix user '$ALLOWUSER'"
groupadd -g 1990 "$ALLOWGROUP"
useradd -u 1991 -m -k /dev/null -s /sbin/nologin "$ALLOWUSER"
usermod -aG "$ALLOWGROUP" "$ALLOWUSER"

# Shadow settings; process either depending on ALLOWUNIXPWD variable existence
_trim="${ALLOWUNIXPWD:-}"
_trim="${_trim// }"
if [ -z "$_trim" ]; then
  # Delete any existing password hash and lock the account
  passwd -d "$ALLOWUSER" >/dev/null 2>&1 || true
  passwd -l "$ALLOWUSER"
else
  # Set the hardly-typeable Unix password
  echo "$ALLOWUNIXPWD" | passwd --stdin "$ALLOWUSER"
fi
# Inspect resulting passwd/shadow entries
echo "Unix user '$ALLOWUSER' was created as below:"
getent passwd "$ALLOWUSER" && getent shadow "$ALLOWUSER"

# Register a Samba user of the exact name
echo -e "\n***Creating Samba user '$ALLOWUSER'\n"
printf '%s\n%s\n' "$ALLOWSMBPWD" "$ALLOWSMBPWD" | pdbedit -a -t -u "$ALLOWUSER"
# Review the properties; this is usually redundant
#pdbedit -Lv "$ALLOWUSER"

# --- Create users to deny access ---
DENYUSER="nonexunix"
# Set it a long and complex password string
DENYSMBPWD="Uk%QuajmoHynejyiavojnaQuapByarz2"

# Create an OS account; a group of the same name is also created
echo -e "\n***Creating Unix user '$DENYUSER'"
useradd --system -s /sbin/nologin "$DENYUSER"
echo "Unix user '$DENYUSER' was created as below:"
getent passwd "$DENYUSER" && getent shadow "$DENYUSER"

# Register a Samba user of the exact name
echo -e "\n***Creating Samba user '$DENYUSER'\n"
printf '%s\n%s\n' "$DENYSMBPWD" "$DENYSMBPWD" | pdbedit -a -t -u "$DENYUSER"
# Set "disabled" flag to prevent any login attempts
pdbedit -r -u "$DENYUSER" -c '[D]'
# Review the properties; this is usually redundant
#pdbedit -L -v -u "$DENYUSER"

# --- Create shared directory ---
SHAREDDIR="/data/sharedstore"
# When the share resides on a separately mounted filesystem,
# a newly mounted filesystem tends to have the label "unlabeled_t".
# Samba (smbd_t) cannot traverse such directory trees ("default_t" is fine).
# This flag is used to decide how broadly we adjust SELinux labels:
# - If set to yes|true, the entire mount point of SHAREDDIR is considered
#   dedicated to Samba shares, and we may label the whole volume.
# - Otherwise, we only touch the specific share directory subtree.
VOLUME_IS_SMB_DEDICATED=no

echo -e "\n***Preparing the directory to share"
mkdir -p "$SHAREDDIR"
chown root:"$ALLOWGROUP" "$SHAREDDIR"
# Set SGID bit so group is inherited to newly added sub-components.
chmod 2775 "$SHAREDDIR"

# Prepare SELinux context labels for the share directory,
# depending on VOLUME_IS_SMB_DEDICATED.
#
should_fix_mountpt_label () {
  # Only consider non-root mount points
  if [ -n "$mountpt" ] && [ "$mountpt" != "/" ]; then
    case "$VOLUME_IS_SMB_DEDICATED" in
      Yes|YES|yes|True|TRUE|true|1)
        return 1;;
      *)
        return 0;;
    esac
  fi
  return 1
}

mountpt="$(findmnt -no TARGET -T "$SHAREDDIR" 2>/dev/null)"

echo -e "\n***Preparing SELinux context labels for the share directory"
if should_fix_mountpt_label; then
  # Extract SELinux type (from user:role:type:level)
  scon_t="$(ls -dZ -- "$mountpt" | awk '{print $1}' | awk -F: '{print $3}')"

  if [ "$scon_t" = "unlabeled_t" ]; then
    echo "Mount point '$mountpt' where '$SHAREDDIR' resides has problematic SELinux type '$scon_t'."
    read -r -p "Reset it with restorecon? [y/N]: " fixtype
    case "$fixtype" in
      y|Y|yes|YES|Yes)
        restorecon -v -- "$mountpt"
        scon_t_post="$(ls -dZ -- "$mountpt" | awk '{print $1}' | awk -F: '{print $3}')"
        if [ "$scon_t_post" != "$scon_t" ]; then
          echo "Fixed SELinux scontext type of mount point '$mountpt' to '$scon_t_post'"
        else
          echo "Failed to fix SELinux scontext type; please check manually later."
        fi
        ;;
      *)
        echo "User canceled fixing SELinux scontext type of '$mountpt'; please check manually later."
        ;;
    esac
  fi
fi

# If the whole volume is dedicated to Samba, label the entire mount point.
# Otherwise, label only the specific share directory subtree.
case "$VOLUME_IS_SMB_DEDICATED" in
  Yes|YES|yes|True|TRUE|true|1)
    sconbasedir="$mountpt"
    should_fix_lostfound=1
    ;;
  *)
    sconbasedir="$SHAREDDIR"
    ;;
esac

# If we label the whole mount point for Samba, make sure "lost+found" directory
# keeps the proper "lost_found_t" type with file class "directory".
if [ "$should_fix_lostfound" -eq 1 ]; then
  semanage fcontext -a -f d -t lost_found_t "${mountpt}/lost\+found" \
    || semanage fcontext -m -f d -t lost_found_t "${mountpt}/lost\+found"
fi

semanage fcontext -a -t samba_share_t "${sconbasedir}(/.*)?" \
  || semanage fcontext -m -t samba_share_t "${sconbasedir}(/.*)?"

# Apply SELinux labels to the selected base directory (either the share
# directory itself or its entire mount point).
# NOTE:
# - In general, using 'restorecon -F' (force) should be avoided,
#   because it resets any custom SELinux labels under the target path.
# - However, here we assume this tree is dedicated to Samba and has no
#   intentional custom labels, so we deliberately use -F.
restorecon -FRv -- "$sconbasedir"
ls -lZa -- "$sconbasedir"

echo -e "\n***Samba base environment was successfully provisioned."
