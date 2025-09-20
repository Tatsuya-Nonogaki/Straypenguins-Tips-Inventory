# Utility scripts for OpenSSL

## What this project is for

This sub-folder in the [Straypenguin's Tips Inventory](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory) provides several tiny utility scripts for OpenSSL.

---

## Contents Summary

### 🔧 cert-pair-check.sh
**Check if the geven keyfile and certificate file is a correct pair:**
**Usage:** `cert-pair-check.sh KEYFILE CRTFILE`

### 🔧 gen-selfsgncert.sh
**Generates a private key and self-signed certificate pair:**
**Usage:** `gen-selfsgncert.sh`

> No arguments are required. Set `SSLCONF` variable in the script file to your tailored SSL conf, or comment it out if you want the system's standard openssl.cnf to be used.
> Attached `openssl-selfsgn-sample.cnf` includes CN `altName` attributes. If you want to use this configuration file, set its path to the `SSLCONF`.
> When the extension is needless, comment out those below:
> ```ini
> copy_extensions = copy   in section [CA_default]
> subjectAltName = @alt_names   in [v3_ca]
> ```
> You can leave `[alt_names]` section which is ignored when above are deactivated.
