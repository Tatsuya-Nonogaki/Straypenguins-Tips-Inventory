# 【GitHub Pages + Jekyll】Markdownリンクの自動変換挙動まとめ（2025年版）

## 概要
GitHub PagesでJekyllを使ってMarkdownドキュメントをサイト化する際、  
「Markdown内のリンクをどう書くべきか？」「.md/.html混在問題は？」  
と悩む方も多いのではないでしょうか。

2024年時点のGitHub Pagesでは、  
**jekyll-relative-linksプラグイン**などの標準搭載機能により、  
「.mdへの相対リンクを書くだけで、HTMLサイトでも切れない・最適なリンク変換」が自動で行われます。

ここでは、実際の挙動とその仕組み、ベストプラクティスを整理します。

---

## 1. 3種類の実際の挙動パターン

### （1）README.mdの存在するフォルダへの相対リンク
- 例: `Linux/OpenSSL/`
    - **HTML生成時:** そのまま (`Linux/OpenSSL/`)
    - **HTMLブラウズ時:**  
      フォルダ配下の`README.md`が`index.html`として自動生成 → `/Linux/OpenSSL/` で表示

### （2）README.mdへの相対リンク
- 例: `vSphere/vcsa-cert-replace-procedures/README.md`
    - **HTML生成時:**  
      `/Straypenguins-Tips-Inventory/vSphere/vcsa-cert-replace-procedures/`  
      （絶対パス化、拡張子なし、README.md指定でもindex.html扱い）
    - **HTMLブラウズ時:**  
      index.htmlが表示される

### （3）README.md以外の.mdファイルへの相対リンク
- 例: `vcsa-cert-replace-procedures.md`
    - **HTML生成時:**  
      `/Straypenguins-Tips-Inventory/vSphere/vcsa-cert-replace-procedures/vcsa-cert-replace-procedures.html` へ自動書き換え
    - **HTMLブラウズ時:**  
      ファイルが.htmlとして生成され、表示される

---

## 2. この自動変換の仕組み：jekyll-relative-linksプラグイン

GitHub Pagesでは、**jekyll-relative-links**というプラグインが標準で有効になっています。

- Markdown内の`.md`への相対リンクが、HTML化時に自動で`.html`リンクに書き換えられる
- README.mdへのリンクはディレクトリ直下のパスに（＝index.html扱い）

このため、**ドキュメントを書く際は「.md」リンクで書くだけでOK**。  
あとから.htmlに直したり、リンク切れを心配したりする必要はありません。

---

## 3. 公式情報・参考リンク

- [About GitHub Pages and Jekyll](https://docs.github.com/en/pages/setting-up-a-github-pages-site-with-jekyll/about-github-pages-and-jekyll)  
  → 「GitHub Pagesで標準有効なプラグイン一覧」として`jekyll-relative-links`も明記

- [jekyll-relative-links 公式リポジトリ](https://github.com/benbalter/jekyll-relative-links)

---

## 4. 運用Tips・ベストプラクティス

- **.md拡張子でリンクを書けば、GitHub WebでもPages HTMLでも両対応できる**
- どうしても両方のURL（GitHub Web/.md と Pages/.html）を明示したい場合のみ、二重リンクを併記
- `_config.yml`に余計なプラグイン追加や設定は不要（むしろ不要なカスタマイズは競合リスク）

---

## 5. まとめ

- 現在のGitHub Pages + Jekyllなら、リンク書式は「普通の.mdリンク」で十分！
- 標準プラグインのおかげで、リンク切れを心配せずMarkdownドキュメントをHTMLサイト化できる
- 古い記事の「リンク書き換え」や「余計なプラグイン追加」は不要

---
