### 全体方針
- 運用上のニーズや対象となる証明書種別、必要な機能に応じて、2つのツール `vCert` と `fixcerts.py` を使い分けていくのが賢いやり方です。どちらのツールも堅牢かつ信頼性は十分で、状況によっては併用することで柔軟性や成功率が向上します。
  > **柔軟な対応力:** いずれかのツールで何らかの制約にぶつかったり、特定のタイプの証明書だけうまく行かなかった場合には、もう一方のツールへとシームレスに切り替えるのも選択肢です。本手順書はこうした「ツール間のフェイルオーバー」を勘案しており、どのような状況でも証明書の更新作業が継続できるよう配慮しています。

  > **補足:** `fixcerts.py` には大きな利点、更新する証明書の有効期間を指定できる機能（`--validityDays <DAYS>`）があります。  
  > ただし、実際に発行される証明書の有効期間は **vCSAのルートCAの有効期限を超えることはできません**。長い期間を指定しても、証明書の有効期限はルートCAと同じになることに注意してください。

  > **補足:** ツールごとに、一部の証明書に関する一部の機能が欠けていたりするため（例えば STS証明書）、もし `fixcerts.py` を主として使用する場合でも、`vCert` も用意しておくことをお勧めします。STS証明書は、VECS CLI や `fixcerts.py` では情報の確認ができません。

- 可能な限り、ターミナルアプリケーションのログ保存機能を有効にしてください。  
  `vCert.py` や `fixcerts.py` の操作は、`PuTTY` やOS標準の `ssh` などによるSSHセッション上で実施することを強く推奨します。

#### 更新前チェックリスト
- **作業前には必ず対象のvCSAのコールドスナップショット（シャットダウン後）を取得してください。**
- 変更前に、現在の証明書の状態を一覧取得します。まず、下記ワンライナーで、VECS管理下の証明書の情報を取得します。
    ```
    for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list | grep -v TRUSTED_ROOT_CRLS); do echo "[*] Store :" $store; /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text | grep -ie "Alias" -ie "Not Before" -ie "Not After"; done
    ```
    > これをスクリプトファイルとして別体にした `list-vecs-certs.sh` も掲載しています。より簡便に使うことができるでしょう。

- 次に、`vCert.py` を使用して、STS証明書、およびExtension用の証明書指紋の情報を採ります。（`vecs-cli`利用の上記ワンライナーでは網羅していないため）:
    ```
    ./vCert.py --run config/view_cert/op_view_11-sts.yaml
    ./vCert.py --run config/check_cert/op_check_10-vc_ext_thumbprints.yaml
    ```
    > **補足:** STS証明書やExtension Thumbprintsの情報を見ることは VECS CLI や `fixcerts.py` ではできないため、 `fixcerts.py` をメインに使う場合にも、`vCert` が使えるように準備しておく必要があります。2行目のチェックは `vCert.py` の "1. Check current certificate status"（または "--run config/op_check_cert.yaml" オプション付きで vCert.pyを実行）にも含まれます。

- vCenter Serverのヘルスチェック  
  - サービス状態（VAMIからもグラフィカルに確認可能）  
     ```
     service-control --status --all
     ```
  - 事前のエラー履歴確認（より慎重にやる場合）:
    - **`/var/log/vmware/vmcad/`**

      重点的に見るファイル:
      - certificate-manager.log  _#Manual certificate operations_
      - vmcad.log                _#VMCA service and certificate lifecycle_ events
      - vmca-audit.log           _#Audit trail of certificate changes_

      さらに見るなら:
      - vmcad-syslog.log         _#system-level VMCA events_

    - **`/var/log/vmware/sso/`**

      重点的に見るファイル:
       - sts-health-status.log    _#STS health and certificate issues_
       - ssoAdminServer.log       _#SSO server operations and errors_
       - vmware-identity-sts.log  _#Secure Token Service (STS) and identity events_

      さらに見るなら:
       - tokenservice.log         _#Token service operations_
       - sso-config.log           _#SSO configuration changes/events_
       - openidconnect.log        _#OpenID Connect related authentication events_

  - ストレージ使用率の確認:
    **ディスクパーティションが枯渇しそうになっていないか、特に `/storage/log`**
    ```
    df -h
    ```
    or
    ```
    df -h /storage/log
    ```
    > **警告:**  
    > `/var/log/vmware` ディレクトリ (`/storage/log` パーティション上) が満杯またはそれに近い状態になっていると、証明書管理操作が失敗したり、vCSA上のサービスの動作不良や停止につながります。  
    > 作業を始める前に、各パーティションに十分な空きがあることを確認してください。  
    > 容量不足が見受けられる場合には、証明書の更新に臨むより先に  [vCenter log disk exhaustion or /storage/log full](https://knowledge.broadcom.com/external/article/313077/vcenter-log-disk-exhaustion-or-storagelo.html) を参照し、原因の調査方法や空きを作る方法を調べるとよいでしょう。

#### 更新後チェックリスト
必要なすべての証明書の更新が終わったら、 基本的なことですが、vCenter Serverおよび証明書の健全性の確認が必要です。
- 例のワンライナーおよび、`vCert.py`を活用した STS証明書やExtension用証明書指紋のチェックを行うコマンドを再度実行し、入れ替えたすべての証明書の有効期限と整合性を確認します。
- vCenter Server上のサービスの健全性を確認します。
  ```
  service-control --status --all
  ```
- `/var/log/vmware/vmcad/` と `/var/log/vmware/sso/` の該当するログに、エラーやアラートが出ていないことを確認します。
- vCenterのUI (vSphere Client, VAMI)で、証明書関係のアラート が出ていないか、サービスが正常に稼働しているかを確認します。
- 環境下に、vCenter Serverへの接続を必要としているバックアップソフト、モニタリングソフト、オートメーションソフトなど（例えば Veeam Backup & Replication）がある場合には、 新しい証明書を取り込ませるためにコンポーネントや定義の更新や再設定が必要になることがあります。これは、 Machine SSL certificate あるいは Root CA certificate を更新した時などによく起こります。

---

### vCertの手順
`vCert.py` は、基本的にインタラクティブメニューで使うように作られています。コマンドラインでのオペレーションの決め打ちは `--run` オプションに続けてディレクトリ配下の `yaml` ファイルパスを指定する形式のためタイプ数が多くなりがちで、それ以外のオプションもかなり限られています。
ただし、時と場合によっては、`--run` でのオペレーション決め打ちが適していることもあります。別紙 `vcsa-cert-list-chart.md` の表 **vCert.py direct operation arguments** に、オペレーション区分毎の `yaml` ファイルパスをまとめてありますので、ご活用ください。

#### 手順
1. **vCert.pyの起動:**  
   ただ簡潔に `./vCert.py` を実行してください。`--user <user@vphere> --password <pswd>` を加えると、特権作業の度に求められる認証が省略できます。

2. **証明書状態の確認:**  
   メインメニューで"1. Check current certificate status"を選択し、状態を確認します。

3. **まずは自動一括更新を試してみる:**  
   メインメニューで"6. Reset all certificates with VMCA-signed certificates"を選択します。

4. **サービス再起動プロンプト:**  
   "Restart VMware services [N]: "の問いには、成功/失敗に関わらず"N"（デフォルト）で応答します。

5. **vCert.py実行後のログ確認（より慎重にやる場合）:**  
   - `/var/log/vmware/vmcad/` と `/var/log/vmware/sso/` を確認し、証明書更新の問題がないかチェックします。
   - vCert.py自体のログも確認してください。公式ドキュメントにこう書かれています、  
     > スクリプトは `/var/log/vmware/vCert/vCert.log` を生成します（これはサポートバンドルにも含められる）。また `/root/vCert-master` 配下にYYYYMMDD形式のディレクトリが作成され、ステージングやバックアップ等のサブディレクトリが格納されます。証明書バックアップ以外の一時ファイルはツール終了時に削除されます。

6. **更新後の検証・サービス再起動:**  
   - 証明書の再作成が成功した場合は、メインメニューで"8. Restart services"を選択してください（ある程度の時間を要す）。
   - サービス再起動後、再度ワンライナーで証明書の有効期限が更新されているか確認します。
   - vCenter管理画面で証明書関連の警告やアラートが出ていないかも確認します。

7. **更新に失敗した場合:**  
   1. メインメニューで"1. Check current certificate status"を選び、失敗した証明書を特定します。
   2. 前述のワンライナーコマンドでも再度状態を確認します。
   3. メインメニュー"3. Manage certificates"から、失敗した証明書タイプごとに再生成を試みます（例："2. Solution User certificates"など）。再度ステータスを確認してください。
      > 証明書の種類とメニュー項目の対応は別紙`vcsa-cert-list-chart.md`の表 **vCert.py Operation for each certificate** 参照。
   4. いずれかでも証明書が更新された場合は、Extensionのための証明書指紋の整合性を確認するために、メインメニューで "3. Manage certificates" => "6. vCenter Extension thumbprints" を選択（または直接 `./vCert.py --run config/manage_cert/op_manage-vc-ext-thumbprints.yaml`）し、そこで MISMATCH が見つかった場合には、"Y"で進み修正します。
   5. 全ての失敗証明書が更新できたら、メインメニューに戻り"8. Restart services"を選択します（ある程度の時間を要す）。

8. **最終ヘルスチェック:**  
   vCSAの健全性と証明書の有効性を確認します。詳しくは、当文書の冒頭の「全体方針」にある「更新後チェックリスト」の節を参照のこと。

---

**Tips:**
- **変更前には必ず静止スナップショットを取得！**  
- **更新後はワンライナーと管理画面で有効期限＆警告チェック！**
- **主要操作ごとにログを確認！ 隠れたエラーも見つかる可能性**

---

### fixcerts.pyの手順
`fixcerts.py`は、時々、安定性に難があるとの報告もあり、証明書ごとに更新の成否が分かれることがあります。それも踏まえ、**一括更新ではなく証明書タイプごとの段階的な更新をお勧め**します。また、必ず最新版（執筆時点では`3_2`）を使用してください。

#### 手順
1. **証明書タイプごとにfixcerts.pyを実行:**  
   - 証明書タイプごとにコマンドを個別実行してください。例:
     ```
     ./fixcerts.py replace --certType machinessl --validityDays 3650 --serviceRestart False
     ```
     **ポイント:**  
     - 各実行時は`--certType`を該当するタイプに変更してください。  
       *（例: `machinessl`, `solutionusers`, `sms`, `data-encipherment` など。証明書の種類と引数名の対応は別紙`vcsa-cert-list-chart.md`の表 **fixcerts.py Operation for each certificate** 参照。）*
     - 有効期間を延長したい場合は`--validityDays`で指定できます。  
       **注:** 実際の証明書発行期間は**ルートCAの期限を超えません**。長い期間を指定しても、証明書はルートCAの期限と同じになります。
     - 各実行時は必ず`--serviceRestart False`を指定します。サービスの再起動は全更新完了の後に一括で行います。
     - 詳細なログ出力が必要な場合は`--debug`オプションを追加することもできます。
     - すべての操作はSSHセッション上で行い、「ログの保存」機能を有効にした状態で行うことを推奨します。
     - **注:** `fixcerts.py`にはインタラクティブメニューはありません。すべてコマンドライン引数で操作します。

2. **各タイプ更新後の証明書検証:**  
   - 各証明書タイプ更新後、**更新前チェックリスト** でも紹介したワンライナー（または別体の `list-vecs-certs.sh`）で、期限が更新されているか確認してください。
     ```
     for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list | grep -v TRUSTED_ROOT_CRLS); do echo "[*] Store :" $store; /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text | grep -ie "Alias" -ie "Not Before" -ie "Not After"; done
     ```
   - STSまたはlookupservice関連の証明書を更新した場合は、
     ```
     ./vCert.py --run config/view_cert/op_view_11-sts.yaml
     ```
     を実行し、有効期限が延長されているか確認します。
   - 更新されていない証明書がないか確認してください。

3. **実行ごとにログを確認（より慎重にやる場合）:**  
   - 標準のシステムログを確認してください:
     - `/var/log/vmware/vmcad/`
     - `/var/log/vmware/sso/`
   - `fixcerts.py`自体のログファイルも確認してください:  
     - 実行時のカレントディレクトリに`fixcerts.log`が出力されているはず。

4. **失敗時のトラブルシュート＆再試行:**  
   - 失敗した証明書タイプがあれば、再度`fixcerts.py`で個別実行してください。
   - `--debug`オプションを付与すると、より詳細な出力が得られます。
   - それでも失敗する場合は、`vecs-cli`等を使った手動更新や公式サポートドキュメントの参照を検討してください。
   - いずれかでも証明書が更新された場合は、Extensionのための証明書指紋の整合性を確認するために、
     ```
     ./vCert.py --run config/manage_cert/op_manage-vc-ext-thumbprints.yaml
     ```
     を実行し、そこで MISMATCH が見つかった場合には、"Y"で進み修正します。

5. **全証明書更新後のサービス再起動:**  
   - 全ての証明書タイプの更新が正常に終わったら、下記コマンドでvCSA上のサービスを再起動します:
     ```
     service-control --stop --all && service-control --start --all
     ```
     > これはfixcerts.py内部でも利用されている推奨の方法です。

6. **最終ヘルスチェック＆検証:**  
   vCSAの健全性と証明書の有効性を確認します。詳しくは、当文書の冒頭の「全体方針」にある「更新後チェックリスト」の節を参照のこと。

---

**Tips:**
- **作業前には必ず静止スナップショットを取得！**
- **更新後はワンライナーと管理画面で有効期限＆警告チェック！**
- **主要操作ごとにログを確認！ 隠れたエラーも見つかる可能性**
- **トラブル時は`--debug`オプションを活用！**
