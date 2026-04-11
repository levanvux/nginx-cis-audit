# CIS NGINX Benchmark Hardening

## Overview

This project applies security best practices from the Center for Internet Security (CIS) NGINX Benchmark to harden an NGINX server.

Scope: Section 1 → Section 3

## Objectives

- Reduce attack surface
- Apply least privilege
- Prevent information disclosure
- Improve logging and monitoring

## Scope Summary

- **Modules**: Load only required modules
- **Account Security**: Non-privileged, locked, no shell
- **Permissions**: Root ownership, restricted access
- **Network**: Only required ports, safe timeouts
- **Information Disclosure**: Hide server details, block sensitive files
- **Logging**: Enable detailed logs and proper configuration

## Automation

Custom scripts are used to audit configurations and return PASS / FAIL results.

## Usage

### Prerequisites

- Root privileges   
- NGINX installed and running  
- Linux-based system (Ubuntu, CentOS...) 
- Bash shell  

### Run the Audit Script

1. Make the script executable:
```bash
chmod +x nginx_cis_audit_s1_to_s3.sh
```

2. Run the script:
```bash
sudo ./nginx_cis_audit_s1_to_s3.sh
```

# Output

The script evaluates then prints results in the following format:
- `PASS`: Configuration complies with CIS Benchmark
- `FAIL`: Configuration needs remediation
- `INFO`: Informational output

## Reference

https://www.cisecurity.org/benchmark/nginx

