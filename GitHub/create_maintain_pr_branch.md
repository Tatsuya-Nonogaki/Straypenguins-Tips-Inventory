# Creating PR as a Branch and maintain

## Create a branch for PR

1. 'main'を親とする場合
   ```
   git fetch origin
   git switch -c feature/update-config origin/main
   ```
   古い gitの場合:
   ```
   git checkout -b feature/update-config origin/main
   ```

2. ファイルを編集や追加

3. ステージング
   ```
   git add path/to/modified-file.txt
   git add path/to/another-file.txt
   git commit -m "Update config handling and add example cloud-init"
   ```

   1. (オプション) 親の更新を取り込んでおく必要が出た時:
      **リベース派:**
      ```
      git fetch origin
      git rebase origin/main
      ```
      コンフリクトが起きたら解消してから、
      ```
      git add <conflicted-files>
      git rebase --continue
      ```
      **マージ派:**
      ```
      git fetch origin
      git merge origin/main
      ```
      コンフリクトを解消してコミット

4. リモートに push (mainでなくPRブランチのまま)
   ```
   git push -u origin feature/update-config
   ```
   初回は `-u` で upstream を設定しておくと、あとあと楽。  
   内部的に手直ししたい／公開レビューを受ける前に作業を続けたい場合は、Create draft pull request を使って「下書き」にしておくと良い。

## Update PR branch

1. 同PRブランチに追加で更新をpush  
   ファイルを修正したら、
   ```
   git add .
   git commit -m "Address review: fix edge case"
   git push
   ```

## 作業完了後のPRブランチの整理

main を最新にして
```
git checkout main
git pull origin main
```

不要になったブランチを削除（ローカル）
```
git branch -d feature/update-config
```

必要ならリモートブランチも削除
```
git push origin --delete feature/update-config
```

---
