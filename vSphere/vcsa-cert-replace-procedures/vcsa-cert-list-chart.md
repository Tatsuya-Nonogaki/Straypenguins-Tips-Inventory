## 1. vCSA certificate types & terms by different tools

| Store                                 | Alias name in vecs-cli | Name in vSphereClient              | Name in fixcerts.py   | Name in vCert.py                       | Notes                                                                |
|---------------------------------------|------------------------|------------------------------------|-----------------------|----------------------------------------|----------------------------------------------------------------------|
| MACHINE_SSL_CERT                      | MACHINE_SSL_CERT       | MACHINE_SSL_CERT                   | MACHINE_SSL_CERT      | Machine SSL certificate                | Main machine cert                                                    |
| Solution User Certificates [category] | various below          | various below                      | solutionuser          | <various>                              | Each is its own cert below                                           |
| SolutionUser: machine                 | machine                | machine                            | machine               | machine                                |                                                                      |
| SolutionUser: vsphere-webclient       | vsphere-webclient      | vsphere-webclient                  | vsphere-webclient     | vsphere-webclient                      |                                                                      |
| SolutionUser: vpxd                    | vpxd                   | vpxd                               | vpxd                  | vpxd                                   |                                                                      |
| SolutionUser: vpxd-extension          | vpxd-extension         | vpxd-extension                     | vpxd-extension        | vpxd-extension                         |                                                                      |
| SolutionUser: hvc                     | hvc                    | hvc                                | hvc                   | hvc                                    | Usually present; check if needed                                     |
| SolutionUser: wcp                     | wcp                    | wcp                                | wcp                   | wcp                                    | For vSphere with Tanzu                                               |
| data-encipherment                     | data-encipherment      | data-encipherment                  | data-encipherment     | data-encipherment certificate          | Used for specific encryption                                         |
| SMS                                   | sms_self_signed        | sms_self_signed                    | SMS                   | SMS self-signed certificate            | Self-signed; used by Storage Mgmt Service                            |
| SMS                                   | N/A                    | N/A                                | N/A                   | SMS VMCA-signed certificate            | Not always present                                                   |
| SMS                                   | sps-extension          | sps-extension                      | N/A                   | N/A                                    | May be legacy                                                        |
| STS Signing Cert                      | N/A                    | STS: ssoserverSign (STS_CERT)      | Signing Cert (STS)    | TenantCredential-1 signing certificate | STS signing for SAML tokens                                          |
| STS_INTERNAL_SSL_CERT                 | N/A                    | STS: CA (STS_CERT)                 | STS_INTERNAL_SSL_CERT | N/A                                    | HTTPS endpoint for STS, referenced by Lookup Service (Not a real CA) |
| Root CA                               | TRUSTED_ROOTS          | Trusted Roots: CA (VMCA_ROOT_CERT) | TRUSTED_ROOTS         | CA certificates in VECS                | CA trust chain                                                       |

## 2. fixcerts.py Operation for each certificate
| Store                 | Alias                | fixcerts.py operation                                      |
|-----------------------|----------------------|------------------------------------------------------------|
| MACHINE_SSL_CERT      | __MACHINE_CERT       | replace --certType machinessl                              |
| machine               | machine              | replace --certType solutionusers                           |
| vsphere-webclient     | vsphere-webclient    | replace --certType solutionusers                           |
| vpxd                  | vpxd                 | replace --certType solutionusers                           |
| vpxd-extension        | vpxd-extension       | replace --certType solutionusers                           |
| hvc                   | hvc                  | replace --certType solutionusers                           |
| wcp                   | wcp                  | replace --certType solutionusers                           |
| data-encipherment     | data-encipherment    | replace --certType data-encipherment                       |
| SMS                   | sms_self_signed      | replace --certType sms                                     |
| SMS                   | sps-extension        | replace --certType sms (or manual/legacy)                  |
| SMS                   | <UUIDs>              | Not directly supported in menu; likely manual via vecs-cli |
| STS Signing Cert      | (Signing Cert (STS)) | replace --certType sts                                     |
| STS_INTERNAL_SSL_CERT | N/A                  | replace --certType lookupservice                           |

## 3. vCert.py Operation for each certificate
| Store                 | Alias                | vCert.py menu operation                                                |
|-----------------------|----------------------|------------------------------------------------------------------------|
| MACHINE_SSL_CERT      | __MACHINE_CERT       | Manage vCenter Certificates > Machine SSL certificate                  |
| machine               | machine              | Manage vCenter Certificates > Solution User certificates               |
| vsphere-webclient     | vsphere-webclient    | Manage vCenter Certificates > Solution User certificates               |
| vpxd                  | vpxd                 | Manage vCenter Certificates > Solution User certificates               |
| vpxd-extension        | vpxd-extension       | Manage vCenter Certificates > Solution User certificates               |
| hvc                   | hvc                  | Manage vCenter Certificates > Solution User certificates               |
| wcp                   | wcp                  | Manage vCenter Certificates > Solution User certificates               |
| data-encipherment     | data-encipherment    | Not directly supported?                                                |
| SMS                   | sms_self_signed      | Manage vCenter Certificates > SMS certificates                         |
| SMS                   | sps-extension        | Manage vCenter Certificates > SMS certificates (if applicable)         |
| SMS                   | <UUIDs>              | Not directly supported in menu; likely manual via vecs-cli             |
| STS Signing Cert      | (Signing Cert (STS)) | Manage vCenter Certificates > STS signing certificates                 |
| STS_INTERNAL_SSL_CERT | N/A                  | Not directly supported in menu; use fixcerts.py or manual via vecs-cli |

## 4. vCert.py direct operation arguments 

E.G., `./vCert.py --run config/op_check_cert.yaml`
| Menu Item Label                               | Valid --run Argument                                             |
|-----------------------------------------------|------------------------------------------------------------------|
| Check current certificate status              | config/op_check_cert.yaml                                        |
| View certificate info                         | config/view_cert/op_check_*.yaml                                 |
| Manage certificate                            | config/manage_cert/op_*.yaml or config/manage_cert/*/op_*.yaml   |
| Manage SSL trust anchors                      | config/manage_cert/trust_anchors/op_*.yaml                       |
| Check configurations                          | config/check_config/op_*.yaml or config/check_config/*/op_*.yaml |
| Reset all certificates with VMCA-signed certs | config/op_reset_cert_vmca.yaml                                   |
| ESXi certificate operations                   | config/esxi_cert_actions/op_esxi_action_*.yaml                   |
| Restart service                               | config/restart_service/op_restart_*.yaml                         |
| Generate certificate report                   | config/op_generate_report.yaml                                   |

