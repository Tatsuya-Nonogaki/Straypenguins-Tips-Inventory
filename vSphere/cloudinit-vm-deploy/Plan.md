# cloud-init 対応: Linux VM Deployment Method on vSphere

## 🚀 工程・運用フロー  

### 準備フェーズ
**Template VM 構築**

- 通常通り構築: Red HatサブスクRegister, パッチ適用等
- cloud-init, cloud-utils-growpart 導入
- cloud-initが適用されないよう `/etc/cloud/cloud.cfg.d/99-template-maint.conf` を配置  
  （⇒ 第2フェーズでクローン上から削除）

**—— これより、基本的にデプロイ自動化スクリプト cloudinit-linux-vm-deploy.ps1 により進める ——**  
📍 `cloudinit-linux-vm-deploy.ps1` は3フェーズで構成され、`-Phase` オプションにより **通しで全自動**／**特定のフェーズのみ** での実行が可能。

### 第1フェーズ

1. **自動化スクリプト cloudinit-linux-vm-deploy.ps1 により:** パラメータファイルの値に応じてCPU数、ディスクサイズなどをカスタマイズしたクローンを作成

### 第2フェーズ

1. クローンVMを起動（手動 ／ 起動していない場合は自動化スクリプトが起動）
2. OSとして・cloud-initとしての初期化、`99-template-maint.conf`の削除

📍 初期化に使用するスクリプト内容は `init-for-cloud-init.sh` ファイルとして独立しているため、VMに送り込んでの手動実行も可能: このフェーズは完全手動実行も可能

### 第3フェーズ

1. 自動化スクリプトがパラメータファイルに従って `user-data` 等 cloud-initコンフィグファイルを、雛形ファイルから生成し、それらを含むcloud-init seed ISOを作成・クローンVMにマウント
2. クローンVMを起動 ⇒ cloud-initによる固有化（リソース量、各ディスク最終パーティションの拡張など）が作動

---

## 💡 ポイント・補足

- テンプレートVMの保守・量産母体両立は `99-template-maint.conf` の運用次第で柔軟に実現: 当ファイルが存在するうちは通常のVMとして起動できる
- フェーズ2の初期化コマンドは外部shファイルとして管理することで、送り込み実行・直接配置の両方に対応
- cloud-initコンフィグファイル（`user-data`等）のテンプレートも別体ファイル管理で、適時修正しやすく、Git/履歴管理や多環境展開にも強い
- 自動化は全体を1本のPSスクリプトで制御。フェーズ単位での分割実行・やり直しも容易
- デプロイ自動化スクリプトに与えるパラメータファイルを、cloud-initとの親和性も高いYAML形式とする。そのため、管理サーバのPowerShellに`powershell-yaml`モジュールを導入。管理サーバにインターネット環境がない場合は別PCで`save-module`して*フォルダごと*持ち込めばOK・軽量
- パラメータファイルは3フェーズすべての値を網羅し、成果VM 1台につき1ファイル: 管理・雛形化が容易

---

## 🚀 制作物・工程・ファイル構成リスト

### ⚙️ A. 準備フェーズ・インフラ

- **Template VM本体**
    - `/etc/cloud/cloud.cfg`  
    - `/etc/cloud/cloud.cfg.d/99-template-maint.conf`  
    - cloud-init, cloud-utils-growpart など必要パッケージ

- **PowerShell モジュール （管理・作業サーバに配置）**
    - powershell-yaml/ : フォルダ一式をzip等でアーカイブ（オフライン配布可）

---

### ⚙️ B. デプロイ自動化スクリプト

#### 📋 スクリプト本体（ワンピース構成・フェーズ切替スイッチ付）
- `cloudinit-linux-vm-deploy.ps1`
    - `-Phase` オプションで1,2,3の指定（リスト型引数）
    - 設定ファイルパス指定（-Config オプションなど）

#### 📋 フェーズ共通パラメータファイル（YAML形式、1VM毎に1ファイル）
- `vm-settings.yaml`
    - vSphereインフラ情報 (vCenterホスト名/IP, 接続用クレデンシャルなど）
    - ソースTemplate VM, クローンVMの名前, vCPU, メモリ, ディスク, ネットワークラベル, デプロイ先クラスタ/データストアなど
    - ホスト名, IPスペック, SSH公開鍵, cloud-initで使う各種値など

#### 📋 第2フェーズ用：VN初期化シェルスクリプト
- `init-for-cloud-init.sh`
    - cloud-init clean, machine-idリセット, subscription-manager clean, 99-template-maint.conf削除 などの処理
    - 自動化スクリプトはこれを読み込みVM内へ`Invoke-VMScript`等で送り込み実行する

#### 📋 第3フェーズ用：cloud-initテンプレート
- `user-data.template.yaml`
- `meta-data.template.yaml`
- `network-config.template.yaml`  
自動化スクリプトはこれら雛形ファイル内のプレースホルダーを共通パラメータファイルの値で置換して固有化し cloud-init seedファイルを生成する

---

### ⚙️ C. 補助ファイル

- `README_deploy.md`  
    - 運用手順・設計意図まとめ

---
