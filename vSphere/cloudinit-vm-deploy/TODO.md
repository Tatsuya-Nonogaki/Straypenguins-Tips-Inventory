# TODO: cloud-init Linux VM Deployment Method on vSphere

## 🔜 制作ステップ

1. **ディレクトリ＆雛形ファイルの初期配置**
   - メインスクリプト cloudinit-linux-vm-deploy.ps1:
     プロジェクトフォルダのルートに; 相対指定で他の読み込みファイルが指定しやすい
   - infra/ :
     Template VMの整備に必要なファイル, e.g. req-pkg-cloudinit.txt, enable-cloudinit-service.sh, cloud.cfg/99-template-maint.conf
   - scripts/ :
     メインスクリプトを除くスクリプト類, e.g. init-vm-cloudinit.sh
   - templates/original/ :
     最初に作成する「基本形」のcloud-init seed雛形
   - params/ :
     メインスクリプトに与えるパラメーターファイル; vm-settings.yaml。他の成果VM用のものも置く場合はファイル名を vm-settings-<VMNAME>.yaml とする。
   - spool/{VM_NAME}/ :
     メインスクリプト実行時に自動作成されるフォルダで、ログ、生成済seedファイルが置かれる
   - README.md : 説明書
   - Plan.md（現状維持でOK）

2. **YAMLパラメータファイルの雛形作成**
   - 必須/任意項目コメント付きで「vm-settings.example.yaml」など

3. **cloud-init seedテンプレート（original/）作成**
   - プレースホルダを{curly}や{{jinja}}形式で統一
   - コメントで用途やサンプル値を明記

4. **init-vm-cloudinit.sh**
   - 標準初期化内容＋コメント; 選択肢が多くコメントで収まりきらなければ、バリエーション(e.g. init-vm-cloudinit-foo.sh)作成も考察

5. **PowerShellスクリプト骨子作成**
   - 引数解析・フェーズスイッチ,ログファンクション,VIConnectファンクション
   - パラメータ読込、テンプレート展開、Invoke-VMScriptなどの関数雛形だけでもOK

6. **README.mdベース着手（運用手順/カスタマイズ例/FAQ枠だけでも）**

---

## ⚡️ 最初の実装段階で意識すると良いこと

- まずは「Phase1だけ」「Phase3だけ」など**部分実装→動作確認**でもOK
- テンプレファイルやシェルスクリプトは**最初はシンプルな形から**作り、後でバリエーション・分岐を増やす
- PowerShellスクリプトは**骨組み・ロギング・エラー制御**から作っておくと後が楽
- 「実ファイル・ログ出力先」などは**ディレクトリパス可変化**も考慮しておくと大規模展開時も安心  
   ⇒ 現段階ではとりあえず、
   ```powershell
   $scriptdir = Split-Path -Path $myInvocation.MyCommand.Path -Parent
   $logdir = "$scriptdir/$VMName"
   ```
   という感じ。

---

## 🛠️ 以降の進め方

- **最初は雛形・サンプルを1セット作り、README/Planと突き合わせて検証**
- 動作確認しながら**フェーズごとに細部を詰めていく**
- フィードバックや追加要望が出たらPlan.mdやREADMEに都度反映
