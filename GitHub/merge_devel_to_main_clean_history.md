# Merge `devel` to `main` While Keeping the Branch History Clean

All updates are made in the `devel` branch and merged to `main` via Pull Requests. This is done for security and consistency (as per repository *Rules*).  
However, as updates accumulate, PRs can become cluttered or conflicted, making merges difficult. This guide describes a procedure to keep both branches in sync and avoid such issues.

⚠ **Caution:**  
If you follow the full procedure, unmerged commits in `devel` may be lost. For routine work, it's usually enough to just ["6. Reset devel to match main (after PR is merged)"](#6-reset-devel-to-match-main-after-pr-is-merged).

---

## Quick Summary

1. **Update local repository**
2. **Rebase `devel` onto `main` (resolving conflicts if required)**
3. **Squash commits (optional but recommended)**
4. **Force-push `devel`**
5. **Open & squash-merge PR from `devel` to `main` on GitHub Web**
6. **Reset `devel` to match `main`**

---

## Recommended Procedure

### 1. **Update your local repository**
   ```bash
   git fetch origin
   git checkout devel
   ```

### 2. **Rebase `devel` onto the latest `main`**
   ```bash
   git rebase origin/main
   ```
   - If there are conflicts, resolve them as prompted.
   - After resolving conflicts, continue rebase:
     ```bash
     git add <conflicted-files>
     git rebase --continue
     ```
   - Repeat until rebase completes.

### 3. **(Optional) Squash your commits for a clean history**
   ```bash
   git rebase -i origin/main
   ```
   - Change `pick` to `squash` for all but the first commit, then save and exit.
   - Edit the commit message as prompted.

### 4. **Force-push `devel` to GitHub**
   ```bash
   git push --force-with-lease origin devel
   ```

### 5. **Open & merge a Pull Request from `devel` to `main` on GitHub Web**
   - Confirm the diff only shows your intended changes.  
     > If files are identical, the diff may be empty or minimal.
   - Choose **"Squash and merge"** (or "Bypass rules and Squash and merge" if required).
     > This creates a single, clean commit on `main`.

### 6. **Reset `devel` to match `main` (after PR is merged)**
   - This removes the "ahead/behind" status and prepares `devel` for new work.  
     ```bash
     git checkout devel
     git fetch origin
     git reset --hard origin/main
     git push --force-with-lease origin devel
     ```

---

## Notes

- Always resolve conflicts locally for clarity and control.
- Use squash merges to keep main branch history readable.
- Resetting `devel` after merging avoids endless loops and keeps branches synchronized.

---
