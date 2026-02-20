# Creating and Maintaining a Pull Request Branch

## Create a Branch for a Pull Request

1. Create a PR branch (for example, if the source is `main`):
   ```bash
   git fetch origin
   git switch -c feature/update-config origin/main
   ```
   On older Git environments:
   ```bash
   git checkout -b feature/update-config origin/main
   ```

2. Add or edit files.

3. Stage and commit your changes:
   ```bash
   git add path/to/modified-file.txt
   git add path/to/another-file.txt
   git commit -m "Update config handling and add example cloud-init"
   ```

   1. (Optional) When you need to incorporate updates from the parent branch:

      **Rebase approach:**
      ```bash
      git fetch origin
      git rebase origin/main
      ```
      If conflicts occur, resolve them and then:
      ```bash
      git add <conflicted-files>
      git rebase --continue
      ```

      **Merge approach:**
      ```bash
      git fetch origin
      git merge origin/main
      ```
      Resolve conflicts and commit the merge.

4. Push to the remote (push the PR branch, not `main`):
   ```bash
   git push -u origin feature/update-config
   ```
   For the first push, use `-u` to set the upstream branch; this makes future pushes and pulls easier.  
   If you want to refine the changes locally or continue working before requesting a public review, use **Create draft pull request** to keep the PR in a “draft” state.

## Update the PR Branch

1. Push additional updates to the same PR branch.  
   After modifying files:
   ```bash
   git add .
   git commit -m "Address review: fix edge case"
   git push
   ```

## Cleaning Up the PR Branch After the Work Is Finished

Update your local `main` branch to the latest:
```bash
git checkout main
git pull origin main
```

Delete the now-unnecessary branch locally:
```bash
git branch -d feature/update-config
```
If the remote-tracking branch still appears in `git branch -r` or `git branch -a`,
delete the corresponding remote-tracking branch explicitly:
```bash
git branch -dr origin/feature/update-config
```
Or, to clean up all "ghost" remote-tracking branches at once:
```bash
git fetch --prune origin
```

If needed, delete the remote branch as well:
```bash
git push origin --delete feature/update-config
```

---
