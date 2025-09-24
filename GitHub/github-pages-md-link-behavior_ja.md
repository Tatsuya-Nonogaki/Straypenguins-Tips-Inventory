# GitHub Pages + Jekyll: Markdownリンク自動変換挙動まとめ（2025年版）

## 概要

GitHub Pages（*Pages*）＋Jekyllでドキュメントを書く際に
- `.md`ファイル間の内部リンクはどう書くべき？
- Markdown→HTML変換でリンク切れしない？
- `.md`と`.html`両方のリンクを管理した方がいい？

……と悩む方は多いのではないでしょうか。

**GitHub Pages**（デフォルトのJekyll構成）は、`jekyll-relative-links`などの標準プラグインのおかげで、Markdownリンクを自動的に最適化してくれます。本記事では、2025年9月時点での実験・観察結果をもとに、その挙動や仕組み、ベストプラクティスをまとめます。

📝 **注意:**  
本稿の内容は2025年9月時点の検証・観察に基づきます。将来的に仕様が変更される可能性もあります。

---

### GitHub Web／GitHub Pages + Jekyllにおけるリンクの基本挙動

#### 📌 index.md と README.md の挙動

- **GitHub Web**では、`README.md`が優先的なインデックスファイルとして認識され、`index.md`は無視されます。
- **GitHub Pages（*Pages*）**では、`index.html`がインデックスとして認識されます（これは*Pages*特有ではなく、一般的なHTMLサーバーの標準挙動です）。
- *Pages*は`index.md`と`README.md`両方を`index.html`に変換しようとしますが、両方が同居する場合は「`index.md`が優先され、`README.md`は無視される」という挙動になります。

  📝 **補足:**  
  すでに`README.md`がある状態で`index.md`を追加すると、`index.md`だけが`index.html`として反映されます。逆に`index.md`を削除すると、再び`README.md`が`index.html`として使われるようになります。まれに挙動が不安定な場合もあり、内部処理の競合（race condition）が疑われるケースも観察されました。

#### 📌 私の `_config.yml`

```yaml
plugins:
  - jekyll-sitemap
```

_config.ymlはこの程度のシンプルさです。[運用Tips](#4-運用tips・ベストプラクティス)も参照してください。

---

## 1. 3種類の主なリンク変換パターン

### （1）README.mdを含むディレクトリへの相対リンク

- **Markdown内のリンク例:** `Linux/OpenSSL/`
- **HTML生成時:** リンクはそのまま（`Linux/OpenSSL/`）。
- **HTMLブラウズ時:** `/Linux/OpenSSL/` へアクセスすると、そのディレクトリの`index.html`（元のREADME.md）が表示される。

### （2）README.md自身への相対リンク

- **リンク例:** `vSphere/vcsa-cert-replace-procedures/README.md`
- **HTML生成時:** ディレクトリパス（`/Straypenguins-Tips-Inventory/vSphere/vcsa-cert-replace-procedures/`）に自動で書き換えられる（ファイル名・拡張子なし）。
- **HTMLブラウズ時:** ディレクトリ配下の`index.html`が表示される。

### （3）README.md／index.md以外の.mdファイルへの相対リンク

- **リンク例:** `vcsa-cert-replace-procedures.md`
- **HTML生成時:** `.html`拡張子付きの絶対パス（例：`/Straypenguins-Tips-Inventory/vSphere/vcsa-cert-replace-procedures/vcsa-cert-replace-procedures.html`）に自動書き換え。
- **HTMLブラウズ時:** 対応する`.html`ページが表示される。

---

## 2. この自動変換の仕組み： `jekyll-relative-links` プラグイン

GitHub Pagesでは、[公式ドキュメント](https://docs.github.com/ja/pages/setting-up-a-github-pages-site-with-jekyll/about-github-pages-and-jekyll)に記載の通り、以下のような標準プラグインが有効です。

- `jekyll-relative-links`
- `jekyll-readme-index`
- その他

**jekyll-relative-links**が特に重要です。  
Markdown内での`.md`ファイル間の相対リンクを、自動的に（HTML化時に）`.html`リンクや`index.html`パスに変換してくれます。  
そのため、  
`[タイトル](other-page.md)` や `[タイトル](Subfolder/)` のように普通に書くだけで、公開サイト上でもリンク切れせず、They’ll Just Work™ です。

---

## 3. 参考リンク

- [GitHub Docs: About GitHub Pages and Jekyll](https://docs.github.com/ja/pages/setting-up-a-github-pages-site-with-jekyll/about-github-pages-and-jekyll)  
  （「GitHub Pagesでサポートされるプラグイン」の項を参照）
- [jekyll-relative-links プラグイン公式リポジトリ](https://github.com/benbalter/jekyll-relative-links)

---

## 4. 運用Tips・ベストプラクティス

- **Markdown内のリンクは「.md」やディレクトリ参照で十分**です。  
  わざわざ`.html`に書き換える必要はありません。
- **README.md または index.md は、そのディレクトリの`index.html`として扱われ、ディレクトリパスでアクセスできます。**
- 現状のGitHub Pages仕様では、「README.md（index.mdは不要）」のみを使うのが安全です。
- **GitHub Web（.md表示）とGitHub Pages（.html表示）の両方に配慮したい場合のみ、二重リンク併記もOK**  
  📝 **二重リンク例:**
  > - [vCSA Certificate Replacement](vSphere/vcsa-cert-replace-procedures/README.md) *(GitHub Web)* / [*(GitHub Pages HTML)*](https://tatsuya-nonogaki.github.io/Straypenguins-Tips-Inventory/vSphere/vcsa-cert-replace-procedures/)

- `_config.yml`に`jekyll-relative-links`等のプラグインを手動で追加する必要はありません（標準で有効）。
- `_config.yml`のカスタマイズも、特別な要件がない限りはシンプルに。

---

## 5. まとめ

- **現行のGitHub Pages + Jekyll**は、Markdownリンクを自動的かつ賢く変換してくれる。
- よほど特殊なケースを除けば、リンク切れを心配せずシンプルなドキュメント運用が可能。
- 「リンクを手動で書き換える」「追加プラグインを入れる」といった一昔前の運用は、もはや不要。

---
