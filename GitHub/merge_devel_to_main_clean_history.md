# Merge `devel` to `main` While Keeping the Branch History Clean

## Recommended Procedure

1. **Update your local repository**
   ```bash
   git fetch origin
   git checkout devel
   ```

2. **Rebase `devel` onto the latest `main`**
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

3. **(Optional) Squash your commits for a clean history**
   ```bash
   git rebase -i origin/main
   ```
   - Change `pick` to `squash` for all but the first commit, then save and exit.
   - Edit the commit message as prompted.

4. **Force-push `devel` to GitHub**
   ```bash
   git push --force-with-lease origin devel
   ```

5. **Open a Pull Request from `devel` to `main` on GitHub Web**
   - Confirm the diff only shows your intended changes.
   - If files are identical, the diff may be empty or minimal.

6. **Merge the PR (Squash and Merge)**
   - Choose **"Squash and merge"** (or "Bypass rules and Squash and merge" if required).
   - This creates a single, clean commit on `main`.

7. **Reset `devel` to match `main` (after PR is merged)**
   ```bash
   git checkout devel
   git fetch origin
   git reset --hard origin/main
   git push --force-with-lease origin devel
   ```
   - This removes the "ahead/behind" status and prepares `devel` for new work.

---

## Notes

- Always resolve conflicts locally for clarity and control.
- Use squash merges to keep main branch history readable.
- Resetting `devel` after merging avoids endless loops and keeps branches synchronized.

---

## Quick Summary

1. Rebase `devel` onto `main`
2. Squash commits (optional but recommended)
3. Force-push `devel`
4. Open and squash-merge PR
5. Reset `devel` to match `main`
