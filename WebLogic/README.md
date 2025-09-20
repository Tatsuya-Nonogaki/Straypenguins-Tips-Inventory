# WebLogic: Automation & Configurations for Administrators

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
**Check the tool components are coded to do what you intend, before use!  
NO WARRANTY for Middleware Operational Beakdown!**

### [automation-wlst/](automation-wlst)
Automation scripts leveraging WebLogic Scripting Tool (WLST). Each subfolder contains:
- A `.py` WLST script (core logic)
- A `.sh` wrapper (shell script for execution)
- `.properties` files (connection/config parameters, not required in a few cases)

#### Provided Automation Modules

- **change_server_listenport/**  
  Change or list the non-SSL listen port for a specific WebLogic Server instance (e.g., 7003 => 7004).

- **log_settings/**  
  Automate log rotation and WebServer extended log format settings.
  - `log_settings_admin/`: For AdminServer (extended log format doesn't apply)
  - `log_settings_ms/`: For Managed Servers

- **set_default_stagingmode/**  
  Configure the default deployment staging mode (`stage`/`nostage`) for a server.

- **set_machine_nmtype/**  
  Set the NodeManager type (`SSL` or `Plain`) for a machine. Useful when managing server instances by NodeManager.

- **set_autorestart/**  
  Enable or disable the AutoRestart setting for a given server. Useful when managing server instances by NodeManager.

- **set_restartdelaysec/**  
  Set the restart delay (in seconds) for a server. Use with the `set_autorestart` tool.

- **set_maxreqparamcount/**  
  Define the maximum number of HTTP request parameters (`MaxRequestParameterCount`) for a server.

---

### profile.d/
- **oracle.sh**  
  Profile script to set environment variables (`ORACLE_HOME`, `WL_HOME`, `DOMAIN_HOME`) and ulimits for the `oracle` user. Adjust as you need.
  > ⚠️ **A lot of Automation-WLST scripts read-in this file** to ensure environment variables. Most of them won't function properly without deploying this file.

---

### rsyslog/
- **rsyslog-rules+.txt**  
  Example `rsyslog` rules to redirect `journald` logs for WebLogic server instances to `/var/log/weblogic/*`, when the servers are run by `systemd`.

---

### systemd/
Systemd service definitions for running WebLogic as managed Linux services.

- **weblogic-admin.service**  
  Unit file for Admin Server

- **weblogic@.service**  
  Template unit for Managed Servers (parameterized by instance name, e.g., "MS1")

- **sysconfig/weblogic-AdminServer**  
  Environment file used by the systemd unit for Admin Server

- **sysconfig/weblogic-MS1**  
  A sample environment file used by the systemd unit for a Managed Server named "MS1". Note the name after `-` speaks.

---

### Top-level Utility Scripts

- **change-wls-java_home.sh**  
  Safely modifies, reports, or backs up `JAVA_HOME` path parameter in WebLogic/Oracle Middleware OUI properties and configuration files. As you may know, we are forced to do a painful series of dirty jobs to update JDK version on a already installed/configured Middleware server.  
  This tool is designed with safety in mind; supplied with "List-only" mode runtime option and in-file hard switch "SAFE_MODE".

  > 💡 **Caution & Tips**
  > The script comes with help contents of a fair amount, shown when `-h` option is given.
  > It also provides special how-to **"Procedure Outline: How this script involved in WebLogic Server JDK Replacement"** in a form of comments, which describes practical replacement procedure outline.
  > **Carefully read them before use for successful replacement.**

- **derby-disable.sh**  
  Disables the built-in Java DB (`derby.jar`) startup by renaming `jar` (💀a demo DB; consuming production server resources).

- **jre-securerandom-fix.sh**  
  For JDK 11+: Switches `securerandom.source` from `/dev/random` to `/dev/urandom` in `java.security` to avoid entropy depletion and speed up JVM start.

- **jre8-securerandom-fix.sh**  
  Same as above, but for Java 8, where still `/dev/./urandom` (with a dot in the middle) was required.

---

## 📝 Usage Notes

- Most tools are designed with assumption that WebLogic/Oracle Middleware is installed and run under the privilege of user `oracle` and relevant environment variables are set (see `profile.d/oracle.sh`).
- Many setting scripts expect the credentials and configuration parameters from the `.properties` files —**check and replace them before use**.

---

## 🛡️ Disclaimer

All scripts and configurations are provided as-is, without warranty. Test thoroughly in a non-production environment before applying to live systems.

---

## 🔗 Related

- [Oracle WebLogic Server Documentation](https://docs.oracle.com/en/middleware/fusion-middleware/weblogic-server/)
- [WLST Scripting Reference](https://docs.oracle.com/en/middleware/fusion-middleware/weblogic-server/14.1.2/wlstc/index.html)
