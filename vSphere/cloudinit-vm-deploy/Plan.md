# cloud-init 対応: Linux VM Deployment Method on vSphere
Rev.2

## 🎯 全般的なガイドライン

☑️ 当スクリプトセットのスクリプトファイル、設定ファイルは、より広い層の人々にが使えるよう、コメントなどはすべて英語ベースとする。ただし、READMEのみ、あとで日本語版も制作する可能性あり。

☑️ ファイルの文字コードはすべてUTF-8とする。改行コードは、Linux上で使用するものはLF, Windows上で使用するものはCRLFとする。

☑️ スクリプト Exitコード 基本ルール

| コード | 意味                            | 例                     |
|--------|---------------------------------|------------------------|
| 0      | 正常終了                        |                        |
| 1      | 一般的な実処理エラー            | VM操作、PowerCLI失敗等 |
| 2      | システム/環境/ファイル操作エラー | ディレクトリ作成失敗等 |
| 3      | 引数・入力・設定ファイルエラー   | パラメータ不足/不正等  |

### 環境・スペック

**Infrastructure**

- vSphere 8 u3+ vCSA & Hosts
  - SSO User: administrator@vsphere.local
  - SSO Password: KenFiat50s^
- 管理サーバ
  - Windows Server 2019
  - PowerShell 5.1
  - PowerCLI 13.3+

**Template VM**

- VMName: rhel9-tpl
- OS-Hostnane: rhel9-tpl
- FQDN: rhel9-tpl.backyard.local
- vSphere-Cluster: CLST_A (DRSなし)
- CPU: 2
- Mem: 3GB
- NIC: x1 ens192 (vmxnet3)
- vSphere-Network-Label: Backyard_LAN
- IP: 192.168.1.100/24 GW:.254 DNS:192.168.1.200
- OS: RHEL9(.4+)
- vSphere Datastore: BackyardStore
- Disks: いずれも通常のvmdk   
  1. sda 40GB : Partition#1:/boot/efi/, P#2:/boot, P#3:/ (残り全部)
  2. sdb 2GB  : P#1:swap
  3. sdc 1GB  : P#1:kdump
- User: mainte
  - Password: CachDreik5
  - ssh-authorized-keys: 登録なし

**Example VM (デプロイターゲット)**

- VMName: original01
- OS-Hostnane: original01
- FQDN: original01.production.local
- vSphere-Cluster: CLST_A (DRSなし)
- ESXi-Host: vhost-a01
- CPU: 3
- Mem: 4GB
- NIC: x1 ens192 (vmxnet3)
- vSphere-Network-Label: PROD_LAN01
- IP: 192.168.0.10/24 GW:.254 DNS:192.168.0.201,192.168.0.202
- vSphere Datastore: ProdStore  
  いずれもgrowpartする
  1. sda 45GB : Partition#1:/boot/efi/, P#2:/boot, P#3:/ (残り全部)
  2. sdb 6GB  : P#1:swap
  3. sdc 5GB  : P#1:kdump
- User: mainte
  - Password: CachDreik5
  - ssh-authorized-keys: C:\work\ssh\id_rsa.pub
- デプロイ時package_update: しない
- デプロイ時package_upgrade: しない

---

## 🚀 工程・運用フロー  

### 準備フェーズ
**Template VM 構築**

- 通常通り構築: Red HatサブスクRegister, パッチ適用等  
  （⇒ RHサブスクは第2フェーズでクローン上でクリア）
- `cloud-init`, `cloud-utils-growpart` 導入
- cloud-initが適用されないよう `/etc/cloud/cloud.cfg.d/99-template-maint.conf` を配置:  
  これにより、テンプレートVMの保守と量産母体としての両立が可能に。当ファイルが存在するうちは通常のVMとして起動できる。（⇒ 第2フェーズでクローン上から削除）

**—— これより、基本的にデプロイ自動化スクリプト cloudinit-linux-vm-deploy.ps1 により進める ——**  

### 🎯 cloudinit-linux-vm-deploy.ps1 の仕様骨子

☑️ **cloudinit-linux-vm-deploy.ps1 は3フェーズ構成:**  
`-Phase` オプション（リスト値であり複数指定可）により **通しで全自動**／**特定のフェーズのみ実行** の選択が可能。やり直しも容易。`2,1`のように順序を乱して指定されても常に昇順で実行。`1,3`という飛び石はエラー扱い。

☑️ 各フェーズで致命的エラーが発生した場合は、以降の処理を自動実行しない。

☑️ **VM自動起動/自動停止機能について:**  
勝手に起動やシャットダウンしてほしくない場合もある。`-NoRestart` スイッチを指定すると、下記フェーズ概要中の ⚡ マークのところの起動／停止は行われない。  
**❗例外:** 複数フェーズ指定（例: `-Phase 1.2,3`や `1,2`, `2,3`）された場合には、自動起動・自動停止なしにはシーケンスが成立しないため、`-NoRestart`は無視するものとする。この例外に合致した場合には、最初のフェーズを開始する以前に、"続行するか否か(y/[N])" のユーザープロンプトで指示を仰ぐ。  
- 第2フェーズ最初のブートアップは必須なので無しにはできないので、Start-MyVMファンクション自体に `if (-not $NoRestart)` 条件を内蔵させるわけにはいかない。そのため、第3フェーズ処理完了後の起動には、そこ自体に個別で `if (-not $NoRestart)` 判定を添える。

☑️ **ログや中間生成物(user-dataファイルなど)の出力先:**  
スクリプトのあるフォルダ直下に成果VMのVM名フォルダを作りそこに出力する。スクリプト終了時にも自動削除はせず、「cloud-init seedが "$path" に作られた」旨を表示する。  
ログは常に追記。user-dataなどcloud-init seedファイル類は警告なしに上書き。バックアップ等は使用者範疇とする。

☑️ **ログおよびターミナルアウトプット:**  
スクリプトがエラー中止となった際に、エラーヶ所と到達処理位置が分かるよう、ターミナル（やや簡略に）およびログファイル（ターミナルよりは詳細）への情報出力を行う。ログファイル出力は例えば  
```powershell
function Write-Log {
    param (
        [string]$Message
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -Append -FilePath $LogFilePath -Encoding UTF8
}
```
＿といったファンクション化が望ましいだろう。

☑️ 成果VM毎のパラメータファイルは、cloud-initとの親和性も高く、シンプルでオブジェクトとして取り込め値の取り出しもしやすいYAML形式とする。そのため、管理サーバのPowerShell(v5.x)環境に`powershell-yaml`モジュールの導入を要件とする。小型のためオフライン配布も低負担。（PowerShell v7.5環境では標準機能であり追加不要）

☑️ パラメータファイルは3フェーズすべての値を網羅し、成果VM 1台につき1ファイル: 管理・雛形化が容易

☑️ 第1, 2, 3 フェーズの処理ロジックはそれぞれfunction化。グローバルスコープの switch 分岐ディスパッチャ内から、それらをコールする。ただし、いずれかのフェーズが非常に短いコードで終わる見込みになった場合、ディスパッチャ内に直接コードを書くことも検討可。

☑️ 第2フェーズの初期化コマンドの内容は `init-vm-cloudinit.sh` ファイルとして独立しているため、自動化スクリプトからの直接実行の他、ファイルとして転送しての手動実行やターミナルへのコピー&ペーストなどにも柔軟に対応

☑️ 第3フェーズのcloud-init seedファイル（`user-data`等）のテンプレートも別体ファイル管理で、適時修正しやすく、Git/履歴管理や多環境展開にも強い。

☑️ ISO作成には、Windws機能のwsl2(ubuntu) 内の `genisoimage`を利用。Windows Server 2019でも使用できるはずだが、無理ならば代替手段を検討。wsl ubuntu内からのパス指定が /mnt/c/...と長くなる問題は、ubuntu内で短いパスへシンボリックリンクを作っておくことで対処できる。

☑️ **vCenter Serverへの接続ロジックについて:**  
- 実績のあるファンクション `VIConnect` があるのでそのコード活用。
- 接続パスワードが(またはユーザも)パラメータファイルで指定されていない場合は、事前に`New-VICredentialStoreItem`で管理サーバ上に登録してあるものと解釈する。
- 接続リトライが組み込まれているが、リトライ回数およびインターバルは固定し、パラメータファイルに求めない。ただし、変更もしやすいよう変数化はする(スクリプト冒頭付近で)。

☑️ PSスクリプトのヘッダのスタイルは、私の既存のスクリプトに近いものにする。あとでサンプルを提供する。

### 第1フェーズ

1. **自動化スクリプト cloudinit-linux-vm-deploy.ps1 により:** パラメータファイルの値に応じてCPU数、ディスクサイズなどをカスタマイズしたクローンを作成  
   そのあとの自動起動はしない。

### 第2フェーズ

1. クローンVMを起動（起動していない場合は自動化スクリプトが起動(NoRestartフラグに関わらず)
2. OSとして・cloud-initとしての初期化、サブスククリア、`99-template-maint.conf`の削除など
3. クローンをシャットダウン(⚡)

📍 初期化コマンドは `init-vm-cloudinit.sh` ファイルとして独立しているため手動実行もしやすく、このフェーズは完全に手動で行うことも可能

### 第3フェーズ

1. 自動化スクリプトがパラメータファイルに従って `user-data` 等 cloud-initコンフィグファイルを、雛形ファイルから生成し、それらを含むcloud-init seed ISOを作成・クローンVMにマウント
2. クローンVMを起動(⚡) ⇒ cloud-initによる固有化（リソース量、各ディスク最終パーティションの拡張など）が作動

---

## 🚀 制作物・工程・ファイル構成リスト

### ⚙️ A. 準備フェーズ・インフラ

- **Template VM本体**
    - `/etc/cloud/cloud.cfg`  
    - `/etc/cloud/cloud.cfg.d/99-template-maint.conf`  
    - cloud-init, cloud-utils-growpart など必要パッケージ

- **PowerShell モジュール （管理・作業サーバに配置）**
    - powershell-yaml/ : フォルダ一式をzip等でアーカイブ（ごく軽量なのでオフライン配布も簡単）  
      📌 バージョン目安は今後実機にて確認、PS自体、PowerCLIバージョンについては、スクリプトコメントかREADMEで「ちなみに」程度で触れることも検討

---

### ⚙️ B. デプロイ自動化スクリプト

#### 📋 スクリプト本体（ワンピース構成・フェーズ切替スイッチ付）
- `cloudinit-linux-vm-deploy.ps1`
    - `-Phase` オプションで1,2,3の指定（リスト型引数）
    - 設定ファイルパス指定（-Config オプションなど）

#### 📋 フェーズ共通パラメータファイル（YAML形式、1VM毎に1ファイル）
- `vm-settings.yaml`
   - **1. インフラ系**  
      vCenterホスト名/IP, 接続用クレデンシャルなど
   - **2. VMハードウェア系**  
      ソースTemplate名, クローンVM名前, vCPU, メモリ, ディスク, ネットワークラベル, デプロイ先クラスタ&データストアなど
   - **3. VM OS内部**  
      ホスト名, IPスペック, SSH公開鍵, cloud-initで使う各種設定値など  

    📌 パラメータファイルの必須プレースフォルダをコメントやREADMEなどで解説の予定

#### 📋 第2フェーズ用：VM初期化シェルスクリプト
- `init-vm-cloudinit.sh`
   ```bash
   #!/bin/sh -x
   subscription-manager clean
   subscription-manager remove --all
   cloud-init clean
   rm -f /etc/ssh/ssh_host_*
   truncate -s0 /etc/machine-id
   ```

- 自動化スクリプトはこれを読み込みVM内で`Invoke-VMScript`で実行する

#### 📋 第3フェーズ用：cloud-initテンプレート
- `user-data.template.yaml`
- `meta-data.template.yaml`
- `network-config.template.yaml`  
自動化スクリプトはこれら雛形ファイル内のプレースホルダーを共通パラメータファイルの値で置換して固有化し cloud-init seedファイルを生成する  

📌 基本形は上記の3ファイルを`original/`フォルダに収容。他に比較的使用頻度の高いパラメータは、可能な程度まではこれらファイル内にコメントアウトした形で併記。その範囲に収まらないものは、別のフォルダを用意して格納（例: `minimal/`, `multinic/`）。網羅パラメータ候補:  
- マルチNIC  
- 複数sshkey登録
- パスワード認証

📌 VM OSは RHLE9 を前提として開発。  
- Networkは標準のNetworkManagerで設定されているものとする
- SELinuxはデフォルトのEnforcingのままとし、とくにcloud-initではいじらない。PermissiveやDisableにする場合はデプロイ後に実機上で手動で変更するのが確実

---

### ⚙️ C. 補助ファイル

- `README.md`  
    - 運用手順・設計意図まとめ

---
