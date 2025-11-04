# TODO: cloud-init Linux VM Deployment Method on vSphere

## 🔜 制作ステップ

1. **ディレクトリ＆雛形ファイルの初期配置**
   - メインスクリプト cloudinit-linux-vm-deploy.ps1:
     プロジェクトフォルダのルートに; 相対指定で他の読み込みファイルが指定しやすい
   - infra/ :
     Template VMの整備に必要なファイル, e.g. cloud.cfg, req-pkg-cloudinit.txt, enable-cloudinit-service.sh, cloud.cfg/99-template-maint.cfg とそれらの補助ツールなど
   - scripts/ :
     メインスクリプトを除くスクリプト類, e.g. `init-vm-cloudinit.sh`
   - templates/original/ :
     cloud-init seed ISOに収まることになるcloud-config YAMLファイルのテンプレートファイル
   - params/ :
     メインスクリプトに与えるパラメーターファイル: `vm-settings.yaml`のサンプルである`vm-settings_example.yaml`。実際に他の成果VM用のパラメータファイルを置く場合はファイル名を `vm-settings_{VMNAME}.yaml` とすることを想定(`-Config`でその都度任意のファイル名を与える仕様のため、命名規則には縛られない)。
   - spool/{VMNAME}/ :
     メインスクリプト実行時に自動作成されるフォルダで、ログ、生成済seedファイルが置かれる
   - README.md : 説明書
   - Plan.md（計画・仕様書 :内部用）、TODO.md(当ファイル :内部用メモ)

2. **YAMLパラメータファイルの雛形作成**
   - 必須/任意項目コメント付きで`vm-settings_example.yaml`など

3. **cloud-init seedテンプレート（original/）作成**
   - プレースホルダを `{{jinja}}` 形式で統一
   - コメントで、用途やサンプル値・バリエーションなどを記載

4. **init-vm-cloudinit.sh**
   - 標準初期化内容＋コメント; 選択肢が多くコメントで収まりきらなければ、バリエーション(e.g. init-vm-cloudinit-foo.sh)作成も検討

5. **PowerShellスクリプト骨子作成**
   - 引数解析・フェーズスイッチ,ログファンクション,VIConnectファンクション
   - パラメータ読込、テンプレート展開、Invoke-VMScriptなどの関数雛形だけでもOK

6. **README.mdベース着手（運用手順/カスタマイズ例/FAQ枠だけでも）**

---

## 🛠️ TODO

- ✅ growpart & resizefs はext4である / と sdc1:/var/crash では成功した。cc_resizefs モジュールはどうやらルートデバイスしかファイルシステム拡張しないようだ。ネットで色々調べるとこのモジュールには調整項目が `resize_rootfs:True/False/noblock` しかなさそうだからだ。sdc1は別途の`runcmd`でresize2fs を実行するブロックをuser-data YAML内に生成する仕掛けで対処した。  
しかし、sdb1:swap の場合、(growpartは問題ないはずだが) フォーマットがswapであるため、更に工夫が必要。swapファイルシステムのリサイズはext2系ファイルシステムのようにオンラインではできず、「再フォーマット」するしかない。困るのは、boot init ramにもgrubパラメータにもswapのUUIDが`resume=`パラメータとして書かれていて、再フォーマットするとそれらの再処理も必要となること ーsystemdの自動生成.mountユニットを一旦maskしたりunmaskしたり`grubby --update-kernel ALL --args "resume=UUID=..."`で新しいUUIDに置き換えたりしないと、ブートエラーでブートさえできなくなる。

  ⇒  
  ✅ grubエントリの `resume` パラメータは、ハイバネートでしか使用されないとのこと。よって、以後は、特にテンプレートでは、grubエントリから`resume`パラメータを必ず削除する運用とすることにする。それにより、ロジックの複雑さがかなり軽減される。Copilotとのディスカッションにより、方向性が決まった:
  - PowerShellで複雑な一連の処理を1つのshスクリプトとして組み立てて、それを runcmd でVM内に配置し、実行する方式にする。変数記号`$`をはじめとした特殊文字のエスケープに悩まされるケースが格段に減り、コードが堅牢になる。

- ✅ Note: on [https://cloudinit.readthedocs.io/en/latest/reference/modules.html#runcmd](https://cloudinit.readthedocs.io/en/latest/reference/modules.html#runcmd)  
  When writing files, do not use /tmp dir as it races with systemd-tmpfiles-clean (LP: #1707222). Use /run/somedir instead.

- ✅ スクリプトで準備が完了し最終ブートさせcloud-init処置が適用された後も、ブートする度にcloud-init処理が走っている。seed ISOがアタッチされていようがなかろうが。アタッチされていない時が最悪 ー"system ens192" connectionが空で作られる。少なくとも、
  - ネットワーク
  - ssh keyの再生成  
  は間違いなく起きている。cloud_init_modules, cloud_config_modules, cloud_final_modules のすべてなのか、一部なのか？ 何かが frequency=`always` になっているため、cloud.cfg か user-data seed YAMLので強制上書きが必要？ 当キットは新規デプロイだけを目的としていて、それ以降の将来の変更の自動化 (例えばディスクサイズ変更など) は考察外なので、すべて「初initブートの際のみ」でよい。

  ⇒  
  cloud.cfgでfrequencyをセットする方法で試した。seed ISOがアタッチされた状態なら、何も起こっていない？ように見える。対して、アタッチぜずにブートすると、seed ISOを待っているような待ち時間（NetworkManager-wait-online service起動の箇所で）が発生し、やはりens192はautoとなりDHCPサーバのない当環境ではIPアドレス無しになり、sshkeyは更新され、hostnameはFQDNになってしまう。cloud-init.disabled を置くしかないか。オプショナルな第4フェーズでISOのデタッチ、削除、といっしょにやるのが良いかもしれない。  

  **⇒ ⭐結論:**  
  CDアタッチなしの際には、cloud-initが新たなinstance-id "iid-datasource-none" を生成してしまうことが判明した。よって、デプロイ完了後に /etc/cloud/cloud-init.disabled ファイルの設置によってcloud-init発動を無効化するしか手はない。第4"Close"フェーズ(後述)を新設し、そこでVM OS上に /etc/cloud/cloud-init.disabled ファイルを置く方式とする。多重防御として、cloud.cfgでのFrequencyの明示はしたままにする。

- ❎ NetworkManagerのconnectionプロファイル(例えば"ens192")が、Template VMからクローンされたVMに残っている状態でcloud-init付きブートがキックされると、"System ens192"という新たなプロファイルが作られてしまう。もし、既存のプロファイルが"System ens192"と同名だった場合には、ユーザの作成時の挙動のように、余計なプロファイルは作られないのか？ あるいは、cloud-init YAML で、プロファイル名まで指定することは可能？  
  ネットワーク設定は、NetworkManager直接でなく、レガシーな /etc/sysconfig/network-scripts/ifcfg-ens192 経由でNMへ設定が反映されるようだ (仮にもし netplan経由だった場合はどのファイルが証拠になる？): cloud.cfgの  
  ```  network:
    renderers: ['sysconfig', 'eni', 'netplan', 'network-manager', 'networkd']
  ```
  から 'sysconfig'など無用レンダラーを削除しておくのも手？

  ⇒  
  抑止する確実な方法はない。

- ✅ NetworkManagerのコネクション設定で、"Ignore automatically obtained routes" と "Ignore automatically obtained DNS param" を true/yes にしたいが方法は？

- ✅ netowrk-config_template.yaml に  
  ```
  dhcp6: false
  ipv6: false
  ```
  は書いてあるが、デプロイされたNM設定では IPv6 が Disabled ではなく Ignore になっている。Disabled にしたい。  
  ⇒  
  cloud-init network-configの通常のYAMLパラメータでは強制は不能。user-dataの `{{USER_RUNCMD_BLOCK}}`プレースホルダ置換内容メンバに `[ nmcli, connection, modify, "System $dev", ipv6.method, disabled ]` を追加。そのために、パラメータファイルに "netif*.ipv6_disable: yes" を追加。

- 📌 ネットワークconnectionプロファイルの削除を、クローン後の初期化(Phase-2)に盛り込む。  
  ユーザは、Phase-3でのcloud-init発動ブート時に user-data の中で実処理に使われているので Phase-2 での削除は不可。唯一の保守ユーザであり、同じユーザがuser-dataに定義されていてもネットワークと違って重複作成や上書きされることはないので、事前削除は行わない。

- ✅ 現在は Phase-2 の最後でVMをシャットダウンしているが、それを Phase-3の頭に移したほうが良いのではないか。  
  - Phase-2 で、起動したまま終われば、スクリプト実行がPhase-2単体指定だった場合、手動調整の機会が与えられる。この時点では cloud-init.disbled は削除されているので手動での再ブートはリスク。
  - ✅ その際、「起動したままになっている。調整したければここでするとよい。作業が終わったらシャットダウンしてもよいし、しなければ次のフェーズ(Phase 3)の最初で自動的にシャットダウンされる」とメッセージを出す。
  - Phase-3 の初めのシャットダウンは、既に起動していれば行われないし、-NoRestart で避けることもできるものとする。NoRestart指定の場合、同フェーズの最後のブートもまた抑止されるから問題はなく、かえって使用者に都合が良い(調整・デバグ用)。
  - ✅ このため、Stop-MyVM を Start-MyVM 同様に結果フラグ文字列を return するよう改良する。

- ✅ 上記で発見: `$outNull =` としている箇所を全部 `$null =` に変更する  

- ✅ Phase-3 の終わりに、seed ISO付きブートともに発動したcloud-initの終了まで待って終わりたい。
  - ✅ それ自体は一通りコーディング済み。終了チェックには、(0) /etc/cloud/cloud-init.disabledの存在、(1)`cloud-init status --wait`、(2)`systemctl show cloud-final`、(3) cloud/instance/boot-finished ファイルの存在(ISOアタッチ時のepochより新しいこと) を入れた。
  - ✅ しかし、もし、過去に既に当VMはcloud-initによるデプロイがされたもので且つcloud-init.disabledがない場合、cloudinit_wait_sec いっぱいまでチェックが回ってしまうか、cloud-initがこのrunでは発動していないのに「完了した」という扱いになってしまう。cloud-initのインスタンスIDや状態ファイルなどに基づいて、今回cloud-initが動作しなかったことを確認できないか？
  ⇒  
  cloud-init完了待ちの前に Quick Checkを挿入。cloud-initのステータスやファイルから情報を拾い、完了待ちの短縮やスキップをできるようにする。instance-idも拾えるようにした。

- ✅ その中のcloud-init終了チェックコードの作成中に気づいたこと: 終了チェックで cloud-init.disabled ファイルが存在したら、チェックを即時不合格とし即座にPhase-3を終わることにしたが、そもそも、cloud-init.disabled が存在する場合、Phase-3 の実行 (seed ISOの作成とアタッチ) 自体、無意味なので、初期段階でPhase-3を警告終了すべきではないか。やるとすれば、Phase-3 頭のシャットダウンの直前に、
  1. Invoke-VMScript でVM上で cloud-init.disabled ファイルの存在をチェックし、あれば、シャットダウンさえ行わずに、その旨の警告メッセージとともにスクリプトを終了する。
  2. その時点でVMが停止している場合は、「VMは停止していて、cloud-initの起動がdisableされているかどうか(i.e. cloud-init.disabledの存在)がチェックできないので、proceed anyway」といった警告メッセージを出す。

- ✅ cloudinit-linux-vm-deploy.ps1 のPhase-3末尾に仮で作ったオプション処理セクション  
  ```powershell
    # Optionally remove the seed ISO from the datastore after successful attach IF AND ONLY IF requested in parameters.
  ```
  は、そこに存在する意味がない。この時点では、ISOはVMにアタッチされているため、おそらく削除自体できないか問題が起こる。可能な方針の選択肢:  
  - 単純にこの処理ブロックを抹消。
  - VMからデタッチする処理を前置する。
  - ⭐ 第4の"Close"フェーズとして独立させる(デタッチ付きで)。デプロイ完結以後のcloud-initの発動を無効化する /etc/cloud/cloud-init.disabled の設置も含める。

- 📌 VMが起動している状態でPhase-4でのISOデタッチ処理を走らせると、vSphere ClientまたはVMRC上で「使用中の可能性があるがでタッチするか」のプロンプトが出て、答えるまででタッチ処理がブロックされて進まない、という注意をREADMEに書く。

- 📌 クローズ以後に、パーティションとファイルシステム/swapの拡大だけをさせたい時は？
