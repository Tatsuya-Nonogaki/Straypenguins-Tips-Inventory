# [Utility Scripts for OpenSSL](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory/tree/main/Linux/OpenSSL)

## What this folder is for

This sub-folder of the [Straypenguins-Tips-Inventory](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory) repository provides several simple utility scripts for OpenSSL.

---

## Contents Summary

### 🔧 cert-pair-check.sh
**Checks if the given key file and certificate file are a valid pair.**  
**Usage:**  
```sh
cert-pair-check.sh KEYFILE CRTFILE
```

---

### 🔧 gen-selfsgncert.sh
**Generates a private key and a self-signed certificate pair.**  
**Usage:**  
```sh
gen-selfsgncert.sh
```
No arguments are required.  
- Set the `SSLCONF` variable in the script to point to your custom OpenSSL configuration file, or comment it out to use the system's default `openssl.cnf`.
- The included `openssl-selfsgn-sample.cnf` demonstrates how to set Subject `altName` attributes. To use this file, set its path to `SSLCONF`.
- If you don't need the extensions, comment out these lines:
  ```ini
  copy_extensions = copy       # in section [CA_default]
  subjectAltName = @alt_names  # in section [v3_ca]
  ```
  The `[alt_names]` section can remain; it will be ignored if the above options are commented out.

---
