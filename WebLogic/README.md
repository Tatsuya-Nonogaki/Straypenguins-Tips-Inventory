# WebLogic: Automation & Configuration Snippets for Administrators

This folder is part of the [Straypenguins-Tips-Inventory](https://github.com/Tatsuya-Nonogaki/Straypenguins-Tips-Inventory) repository and provides practical, field-tested automation scripts and configuration snippets for Oracle WebLogic Server administration.

The aim is to help administrators:
- Automate repetitive or error-prone tasks
- Apply proven-in-practice configuration changes
- Save time and labor
- Increase operational reliability

---

## 📂 Folder Structure & Tools

```
WebLogic/
├── automation-wlst/
│   ├── change_server_listenport/
│   ├── log_settings/
│   ├── set_autorestart/
│   ├── set_default_stagingmode/
│   ├── set_machine_nmtype/
│   ├── set_maxreqparamcount/
│   └── set_restartdelaysec/
├── profile.d/
├── rsyslog/
├── systemd/
├── change-wls-java_home.sh
├── derby-disable.sh
├── jre-securerandom-fix.sh
├── jre8-securerandom-fix.sh
```

---

## 🛠️ Contents Breakdown

⚠️ **WARNING:**  
**Verify that the tools do what you intend before use!  
NO WARRANTY for middleware operational breakdowns!**

### [automation-wlst/](automation-wlst)
Automation scripts leveraging WebLogic Scripting Tool (WLST). Each subfolder contains:
- A `.py` WLST script (core logic)
- A `.sh` wrapper (shell script for execution)
- `.properties` files (for connection/config parameters; not required for some tools)

#### Provided Automation Modules

- **[change_server_listenport/](automation-wlst/change_server_listenport)**  
  Change or list the non-SSL listen port for a specific WebLogic Server instance (e.g., 7003 => 7004).

- **[log_settings/](automation-wlst/log_settings)**  
  Automate log rotation and WebServer extended log format settings.
  - `log_settings_admin/`: For AdminServer (extended log format does not apply)
  - `log_settings_ms/`: For Managed Servers

- **[set_default_stagingmode/](automation-wlst/set_default_stagingmode)**  
  Configure the default deployment staging mode (`stage`/`nostage`) for a server.

- **[set_machine_nmtype/](automation-wlst/set_machine_nmtype)**  
  Set the NodeManager type (`SSL` or `Plain`) for a machine. Useful when managing server instances with NodeManager.

- **[set_autorestart/](automation-wlst/set_autorestart)**  
  Enable or disable the AutoRestart setting for a given server. Useful when managing server instances with NodeManager.

- **[set_restartdelaysec/](automation-wlst/set_restartdelaysec)**  
  Set the restart delay (in seconds) for a server. Use together with the `set_autorestart` tool.

- **[set_maxreqparamcount/](automation-wlst/set_maxreqparamcount)**  
  Define the maximum number of HTTP request parameters (`MaxRequestParameterCount`) for a server.

---

### [profile.d/](profile.d)
- **oracle.sh**  
  Profile script to set environment variables (`ORACLE_HOME`, `WL_HOME`, `DOMAIN_HOME`) and ulimits for the `oracle` user. Adjust as needed.
  > ⚠️ **Many Automation-WLST scripts read this file** to ensure environment variables are set. Most scripts will not function properly unless this file is deployed and contains the appropriate values.

---

### [rsyslog/](rsyslog)
- **rsyslog-rules+.txt**  
  Example `rsyslog` rules to redirect `journald` logs for WebLogic server instances to `/var/log/weblogic/*` when the servers are run under `systemd`.

---

### [systemd/](systemd)
Systemd service definitions for running WebLogic as managed Linux services.

- **weblogic-admin.service**  
  Unit file for Admin Server

- **weblogic@.service**  
  Template unit for Managed Servers (parameterized by instance name, e.g., 'MS1')

- **sysconfig/weblogic-AdminServer**  
  Environment file used by the systemd unit for Admin Server

- **sysconfig/weblogic-MS1**  
  Sample environment file used by the systemd unit for a Managed Server named 'MS1'. The name after the `-` corresponds to the server instance.

---

### Top-level Utility Scripts

- **change-wls-java_home.sh**  
  Safely modifies, reports, or backs up the `JAVA_HOME` path parameter in WebLogic/Oracle Middleware OUI properties and configuration files.  
  As you may know, updating the JDK version on an already installed/configured Middleware server often involves a series of tedious and error-prone steps.  
  This tool is designed with safety in mind; it provides a 'list-only' mode runtime option and an in-file 'SAFE_MODE' switch.

  > 💡 **Caution & Tips**
  > The script provides extensive help output, which can be displayed by using the `-h` option.
  > It also provides a detailed 'Procedure Outline: How this script is involved in WebLogic Server JDK Replacement' in the comments, which describes the practical replacement procedure.
  > Be sure to read these instructions carefully for a successful replacement.

- **derby-disable.sh**  
  Disables the built-in Java DB (`derby.jar`) by renaming the jar file (💀 demo DB; can consume production server resources).

- **jre-securerandom-fix.sh**  
  For JDK 11+: Switches `securerandom.source` from `/dev/random` to `/dev/urandom` in `java.security` to avoid entropy depletion and speed up JVM start.

- **jre8-securerandom-fix.sh**  
  Same as above, but for Java 8, which requires `/dev/./urandom` (with a dot in the path).

---

## 📝 Usage Notes

- Most tools assume that WebLogic/Oracle Middleware is installed and run under the `oracle` user, with relevant environment variables set (see `profile.d/oracle.sh`).
- Many scripts expect credentials and configuration parameters to be provided in `.properties` files — **be sure to check and edit these before use**.

---

## 🛡️ Disclaimer

All scripts and configurations are provided as-is, without warranty. Test thoroughly in a non-production environment before applying to live systems.

---

## 🔗 Related

- [Oracle WebLogic Server Documentation](https://docs.oracle.com/en/middleware/fusion-middleware/weblogic-server/)
- [WLST Scripting Reference](https://docs.oracle.com/en/middleware/fusion-middleware/weblogic-server/14.1.2/wlstc/index.html)
