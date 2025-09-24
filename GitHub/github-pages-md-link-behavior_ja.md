# GitHub Pages + Jekyll: Markdownリンク自動変換挙動まとめ（2025年版）

👉 English Edition is also available [HERE](github-pages-md-link-behavior.md)

## 概要

GitHub Pages（*Pages*）＋Jekyllでドキュメントを書く際に
- `.md`ファイル間の内部リンクはどう書くべき？
- Markdown→HTML変換でリンク切れしない？
- `.md`と`.html`両方へのリンクを書いた方がいい？

……といった悩みを持つ方は多いのではないでしょうか。

**GitHub Pages**（デフォルトのJekyll構成）は、`jekyll-relative-links`などの標準プラグインのおかげで、Markdownリンクを自動的に最適化してくれます。本記事では、2025年時点での実験・観察結果をもとに、その挙動や仕組み、ベストプラクティスをまとめます。

📝 **注意:**  
本稿の内容は2025年9月時点の検証・観察に基づいたものです。将来、仕様が変更される可能性があります。

📝 **ちなみに** `jekyll` は「ジキル」あるいは「ジクル」と読みます。あの物語「ジキル博士とハイド氏」"Dr. Jekyll and Mr. Hyde" のそれ、そのものです。

---

### GitHub Web/GitHub Pages + Jekyllにおけるリンクの基本挙動

#### 📌 index.md と README.md の優先順位

- **GitHub Web**では、`index.md`ではなく、`README.md`が優先的なインデックスファイルとして認識されます。
- **GitHub Pages**（以降 *Pages*）では、`index.html`がインデックスとして認識されます（これは*Pages*特有というより、一般的なHTMLサーバーの標準的な挙動であり、jekyllはそれを遵守しているに過ぎない、と言えます）。
- *Pages*は`index.md`と`README.md`のどちらも`index.html`に変換しようとしますが、両方が存在する場合には衝突が起きることになります。その場合、HTMLページ生成アルゴリズムは常に`index.md`を先に検出して変換するため、結果的に`README.md`は無視されます。

  📝 **補足:**  
  すでに`README.md`がある状態で`index.md`を追加すると、`index.md`の方がが変換されて、`index.html`を上書きするかたちになります。そこで今度は`index.md`を削除すると、再び`README.md`から`index.html`が生成されます。希に挙動が不定な場合も見られたようです—レースコンディションが存在するのかもしれません。

#### 📌 私の `_config.yml`

```yaml
plugins:
  - jekyll-sitemap
```

_config.ymlはこのようにシンプルです。[運用Tips](#4-運用tips・ベストプラクティス)も参照してください。

---

## 1. jekyllにおける3つの主なリンク変換パターンでの挙動

### （1）README.mdのあるディレクトリへの相対リンク

- **Markdown内のリンク例:** `Linux/OpenSSL/`
- **HTML生成時:** リンクはそのまま（`Linux/OpenSSL/`）。
- **HTMLブラウズ時:** `/Linux/OpenSSL/` へアクセスすると、そのディレクトリの`index.html`(jekyllによって変換されたもの)が表示される。

### （2）README.mdを指す相対リンク

- **Markdown内のリンク例:** `vSphere/vcsa-cert-replace-procedures/README.md`
- **HTML生成時:** レポジトリのルートから始まるディレクトリパス（`/Straypenguins-Tips-Inventory/vSphere/vcsa-cert-replace-procedures/`）に自動的に書き換えられる（ファイル名なし）。
- **HTMLブラウズ時:** ディレクトリ配下の`index.html`が表示される。

### （3）README.mdやindex.md以外の.mdファイルへの相対リンク

- **Markdown内のリンク例:** `vcsa-cert-replace-procedures.md`
- **HTML生成時:** レポジトリのルートから始まるファイルパスであり、拡張子は`.html`に変換されている。（例：`/Straypenguins-Tips-Inventory/vSphere/vcsa-cert-replace-procedures/vcsa-cert-replace-procedures.html`）
- **HTMLブラウズ時:** 呼応する`.html`ページが表示される。

---

## 2. jekyll-relative-links プラグイン: 自動変換のからくり

GitHub Pagesでは、いくつかの`jekyll`プラグインがデフォルトで有効化されています（[公式ドキュメント](https://docs.github.com/ja/pages/setting-up-a-github-pages-site-with-jekyll/about-github-pages-and-jekyll)）。そこには、以下のようなプラグインが含まれます:

- `jekyll-relative-links`
- `jekyll-readme-index`
- その他

特にキーとなるのが **jekyll-relative-links**:  
Markdown内での`.md`ファイル間相対リンクを、HTML化の際に自動的に、呼応する`.html`（あるいは`index.html`を持つディレクトリ）パスに変換してくれます。  
そのおかげで、単に  
`[Label](other-page.md)` や `[Label](Subfolder/)` といったふうに書くだけで、公開されたサイト上でもリンクが切れせず「つべこべ言わんでもとにかく動く」わけです。

---

## 3. 参考リンク

- [GitHub Docs: About GitHub Pages and Jekyll](https://docs.github.com/ja/pages/setting-up-a-github-pages-site-with-jekyll/about-github-pages-and-jekyll)  
  （「GitHub Pagesでサポートされるプラグイン」の項を参照）
- [jekyll-relative-links プラグイン公式リポジトリ](https://github.com/benbalter/jekyll-relative-links)
- [Jekyll Web Site](https://jekyllrb.com)

---

## 4. 運用Tips・ベストプラクティス

- **Markdown内のリンクは「.md」やディレクトリ参照だけで十分**です。  
  手作業で`.html`版を作る必要はありません。
- **README.md**や**index.md**は、そのディレクトリの`index.html`として変換され、ディレクトリパスだけでもアクセスできます。
- 現状のGitHub Pagesの仕様からすると、`index.md`ではなく`README.md`のみを置くのが最善のようです。
- GitHub Webの`.md`表示とGitHub Pagesの`.html`表示を両方したい場合には、ダブルリンク併記も有効な手段ですが、`.md`へのリンクだけでも十分です。  
  📝 **ダブルリンクの実例:**
  > - [vCSA Certificate Replacement](vSphere/vcsa-cert-replace-procedures/README.md) *(GitHub Web)* / [*(GitHub Pages HTML)*](https://tatsuya-nonogaki.github.io/Straypenguins-Tips-Inventory/vSphere/vcsa-cert-replace-procedures/)

- `_config.yml`に`jekyll-relative-links`等のプラグインを手動で追加する必要はありません（GitHub Pages標準で有効）。
- 手の混んだ`_config.yml`のカスタマイズも、特別な要件でもない限り、無用。

---

## 5. まとめ

- **現行のGitHub Pages + Jekyll**は、Markdownリンクを自動的かつ賢く変換してくれる。
- よほど特殊なケースを除けば、シンプルなドキュメントで、リンク切れの心配はほとんど不要。シンプルな方がドキュメントの維持管理も楽。
- 「リンクをちまちま手動編集」「追加プラグインを書き足す」といった一昔前の運用は、もはや不要かも。

---
