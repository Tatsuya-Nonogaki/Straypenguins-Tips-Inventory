# GitHub Pages + Jekyll: How Markdown Links Are Handled (2025 Edition)

## Overview

When building documentation with GitHub Pages (*Pages*) and Jekyll, many writers wonder:
- How should I write internal links between `.md` files?
- Will links break when converting Markdown to HTML?
- Do I need to maintain both `.md` and `.html` links?

**GitHub Pages** (with its default Jekyll setup) provides powerful, automatic handling of Markdown links—thanks to built-in plugins like `jekyll-relative-links`. This article summarizes behaviors I observed and explains how it all works, so you can write Markdown links with confidence.

📝 **Note:**  
The behavior described in this document is based on my experiments and observations in Sep 2025. They may vary in the future.

### Link Related Basic Behavior on GitHub Web and GitHub Pages + Jekyll

#### 📌 index.md VS README.md

- On GitHub Web, `README.md` is recognized as the primary index, not `index.md`.
- In GitHub Pages (*Pages*), `index.html` is recognized as the primary index. This is not unique to *Pages*, but is standard behavior for HTML servers, which *Pages* follows.
- *Pages* attempts to convert both `index.md` and `README.md` into `index.html`. This naturally causes a conflict when the both coexist. In that case, the page generation algorithm always finds and converts `index.md` first, so `README.md` is ignored.

  📝 **Additional Note:**  
  If you create an `index.md` in addition to an existing `README.md`, `index.md` will be converted to `index.html`, overwriting any previous version. If you then remove `index.md` and leave `README.md`, a new `index.html` will be generated from `README.md`. I have observed some inconsistent results, which may suggest a race condition in the generation process.

#### 📌 My `_config.yml`

```yaml
plugins:
  - jekyll-sitemap
```

My `_config.yml` is this simple. See [Best Practices & Practical Tips](#4-best-practices--practical-tips).

## 1. Three Key Link Conversion Behaviors with Jekyll

### (1) Relative Link to a Directory Containing a README.md

- **Link in Markdown:** `Linux/OpenSSL/`
- **HTML Generation:** The link is left as-is (`Linux/OpenSSL/`).
- **HTML Browsing:** Navigating to `/Linux/OpenSSL/` displays the rendered `index.html`.

### (2) Relative Link Directly to a README.md

- **Link in Markdown:** `vSphere/vcsa-cert-replace-procedures/README.md`
- **HTML Generation:** The link is automatically rewritten to the directory path from the repository root (`/Straypenguins-Tips-Inventory/vSphere/vcsa-cert-replace-procedures/`), with no filename.
- **HTML Browsing:** The directory’s `index.html` is displayed.

### (3) Relative Link to a Non-README/index Markdown File

- **Link in Markdown:** `vcsa-cert-replace-procedures.md`
- **HTML Generation:** The link is rewritten to the file path from the repository root, with suffix replaced with `.html`, such as `/Straypenguins-Tips-Inventory/vSphere/vcsa-cert-replace-procedures/vcsa-cert-replace-procedures.html`.
- **HTML Browsing:** The linked file is available as an `.html` page.

---

## 2. The Mechanism: `jekyll-relative-links` Plugin

GitHub Pages enables several Jekyll plugins by default (see [official docs](https://docs.github.com/en/pages/setting-up-a-github-pages-site-with-jekyll/about-github-pages-and-jekyll)), including:

- `jekyll-relative-links`
- `jekyll-readme-index`
- and others

**jekyll-relative-links** is key:  
It automatically rewrites Markdown links between `.md` files so that, when your site is built, links point to the corresponding `.html` files (or directory paths for `index.html`). This means you can write all your internal links simply as `[Label](other-page.md)` or `[Label](Subfolder/)`, and they’ll Just Work™ in the published site.

---

## 3. References

- [GitHub Docs: About GitHub Pages and Jekyll](https://docs.github.com/en/pages/setting-up-a-github-pages-site-with-jekyll/about-github-pages-and-jekyll)  
  (See the section on "Plugins supported by GitHub Pages")
- [jekyll-relative-links plugin repository](https://github.com/benbalter/jekyll-relative-links)

---

## 4. Best Practices & Practical Tips

- **Write links as `.md` or directory references** in your Markdown files.  
  No need to hand-convert to `.html` for the site!
- **README.md** or **index.md** become `index.html` for their folder, accessible via the directory path.
- Based on GitHub's current implementation, using only `README.md` (and not `index.md`) appears to be the best practice.
- If you want to offer both GitHub Web view (`.md`) and GitHub Pages view (`.html`) to readers,  
  consider dual-linking—but for most use cases, a single `.md` link suffices.  
  📝 **My dual-linking example:**
  > - [vCSA Certificate Replacement](vSphere/vcsa-cert-replace-procedures/README.md) *(GitHub Web)* / [*(GitHub Pages HTML)*](https://tatsuya-nonogaki.github.io/Straypenguins-Tips-Inventory/vSphere/vcsa-cert-replace-procedures/)  

- No need to manually add `jekyll-relative-links` or other plugins in `_config.yml`—they’re enabled by default on GitHub Pages.
- Avoid over-customizing `_config.yml` unless you have a specific requirement.

---

## 5. Summary

- **Modern GitHub Pages + Jekyll** handles Markdown links automatically and smartly.
- You can write clean, maintainable documentation without worrying about link breakage, except in particularly complex situations.
- Old advice about manually adjusting links or adding extra plugins is now outdated.

---
