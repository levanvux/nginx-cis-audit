#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[1;35m'
NC='\033[0m' # No Color

# 1.1 Installation
# 1.1.1 Ensure NGINX is installed 
audit_1_1_1() {
  # Kiem tra xem NGINX co ton tai hay khong
  echo -e "${PURPLE}[1.1.1] Ensure NGINX is installed"
  if ! command -v nginx &> /dev/null; then 
    echo -e "STATUS: [${RED}ERROR${NC}]"
    echo "Detail: NGINX is not installed."
    exit 1
  fi
  
  # Kiem tra phien ban NGINX co phai tu 1.28.0 tro len khong
  CURRENT_VER=$(nginx -v 2>&1 | grep -oP '\d+\.\d+\.\d+')
  compare_ver() {
    echo "$1 $2" | awk '{
      split($1, a, "."); split($2, b,".");
      for (i = 1 ; i < 4; i++) {
        if (a[i] > b[i]) { print "GT"; exit }
        if (a[i] < b[i]) { print "LT"; exit }
      }
      print "EQ"
    }'
  }
  
  if [ "$(compare_ver "$CURRENT_VER" "1.28.0")" == "LT" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "REMEDIATION: update NGINX to version 1.28.0 or higher."
  else 
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: NGINX version is up to date ($CURRENT_VER)."
  fi
  
  echo ""
}


# 1.2.1 Ensure package manager repositories are properly configured
audit_1_2_1() {
  echo -e "${PURPLE}[1.2.1] Ensure package manager repositories are properly configured${NC}"
    
  # Xem nguon package cua NGINX
  REPO_INFO=$(apt-cache policy nginx 2>/dev/null)
    
  if [ -z "$REPO_INFO" ]; then
    echo -e "STATUS: [${RED}ERROR${NC}]"
    echo "Detail: Cannot retrieve NGINX repository policy."
    return 1
  fi

  # Kiem tra xem co chua cac domain tin cay hay khong
  if echo "$REPO_INFO" | grep -qE "nginx\.org|ubuntu\.com|debian\.org"; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    TRUSTED_URL=$(echo "$REPO_INFO" | grep -oP 'https?://\S+' | head -n 1)
    echo "Detail: NGINX repository is trusted ($TRUSTED_URL)."
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "REMEDIATION: Use official NGINX or OS vendor repositories. Check more: apt-cache policy nginx."
  fi

  echo ""  
}

audit_1_2_2() {
  echo -e "${PURPLE}[1.2.2] Ensure the latest software package is installed${NC}"
    
  # Phien ban da cai (Installed) & phien ban moi nhat co san (Candidate)
  INSTALLED_VER=$(apt-cache policy nginx | grep "Installed:" | awk '{print $2}')
  CANDIDATE_VER=$(apt-cache policy nginx | grep "Candidate:" | awk '{print $2}')

  if [ "$INSTALLED_VER" == "$CANDIDATE_VER" ]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: NGINX is at the latest version available ($INSTALLED_VER)."
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: Current version ($INSTALLED_VER) is older than available version ($CANDIDATE_VER)."
    echo "REMEDIATION: Run 'sudo apt update && sudo apt install nginx -y'."
  fi

  echo ""
}

# 2.1 Minimize NGINX Modules
# 2.1.1 Ensure only required dynamic modules are loaded (Manual)
audit_2_1_1() {
  echo -e "${PURPLE}[2.1.1] Ensure only required dynamic modules are loaded${NC}"
  # Tim xem co dynamic modules nao khong
  DYNAMIC_MOD=$(sudo nginx -T 2>/dev/null | grep "load_module"| grep -v '^ *#')

  if [ -z "$DYNAMIC_MOD" ]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: No dynamic modules were detected."
  else 
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: The following dynamic modules were detected:"
    echo -e "${YELLOW} ${DYNAMIC_MOD} ${NC}"
    echo "REMEDIATION: Identify and comment out (#) unnecessary load_module directives in /etc/nginx/nginx.conf. Validate and apply changes: sudo nginx -t && sudo systemctl reload nginx."
  fi
  echo "" 
 	
  echo -e "${PURPLE}[2.1.1.Info] Audit Static Modules${NC}"
  # Tim cac static modules
  STATIC_MOD=$(nginx -V 2>&1 | grep -oEi '\-\-(with|without)-[^ ]*')
  # Kiem tra xem trong STATIC_MOD co modules rui ro nao khong
  RISKY_STATIC_MOD=$(echo "$STATIC_MOD" | grep -E "http_stub_status_module|http_dav_module|http_random_index_module")
  
  echo -e "STATUS: [${BLUE}INFO${NC}]"
  if [ -z "$RISKY_STATIC_MOD" ]; then
    echo "Detail: No risky static modules detected."
  else 
    echo "Detail: The following sensitive static modules were detected:"
    echo -e "${YELLOW}${RISKY_STATIC_MOD} ${NC}"
    echo "REMEDIATION: Ensure directives like 'stub_status' or 'dav_methods' are not enabled in your config unless authorized."
  fi

  echo ""
}

# 2.2 Account Security
# 2.2.1 Ensure that NGINX is run using a non-privileged, dedicated service account (Manual)
audit_2_2_1() {
  echo -e "${PURPLE}[2.2.1] Ensure NGINX runs as a non-privileged service account${NC}"
  
  # Tim user duoc configured
  CONF_USER=$(sudo nginx -T 2>/dev/null | grep "^user" | awk '{print $2}' | sed 's/;//' | head -n 1)
  if [ -z "$CONF_USER" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: No specific 'user' directive found in NGINX configuration."
    echo "REMEDIATION:"
    echo "1. Create system user: sudo useradd -r -d /var/cache/nginx -s /sbin/nologin nginx"
    echo "2. Configure NGINX: Set 'user nginx;' in the main context of /etc/nginx/nginx.conf"
    return
  fi

  # Lay uid va groups cua user 
  USER_ID=$(id -u "$CONF_USER" 2>/dev/null)
  USER_GROUPS=$(id -Gn "$CONF_USER" 2>/dev/null)

  CHECK_SUDO_ACCESS=$(sudo -l -U "$CONF_USER" 2>&1)
  
  IS_FAIL=0

  if [ "$USER_ID" -eq 0 ] || [[ "$USER_GROUPS" =~ root ]] || [[ "$USER_GROUPS" =~ sudo ]] || [[ "$SUDO_CHECK" == *"not allowed to run sudo"* ]]; then
    IS_FAIL=1
  fi

  if [ "$IS_FAIL" -eq 1 ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: User '${CONF_USER}' has excessive privileges (UID: $USER_ID, Groups: $USER_GROUPS)."
    
    echo "REMEDIATION:"
    echo "1. Harden User: Ensure '${CONF_USER}' is NOT in root/sudo groups."
    echo "2. Lock User Account: Run the following commands:"
    echo -e " ${YELLOW}sudo usermod -s /sbin/nologin ${CONF_USER}${NC}"
    echo -e " ${YELLOW}sudo usermod -L ${CONF_USER}${NC}"
  else
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: User '${CONF_USER}' (UID: $USER_ID, Groups: $USER_GROUPS) is a non-privileged service account."
  fi

  echo ""
}

# 2.2.2 Ensure the NGINX service account is locked (Manual)
audit_2_2_2() {
  echo -e "${PURPLE}[2.2.2] Ensure the NGINX service account is locked${NC}"
  CONF_USER=$(sudo nginx -T 2>/dev/null | grep -i "^user" | awk '{print $2}' | sed 's/;//' | head -n 1)
  if [ -z "$CONF_USER" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: No NGINX user identified. Please complete Task 2.2.1 first."
    return
  fi

  # Check lock status
  LOCK_STATUS=$(sudo passwd -S "$CONF_USER" 2>/dev/null)
  if [[ "$LOCK_STATUS" == *" L "* ]] || [[ "$LOCK_STATUS" == *"LK"* ]] || [[ "$LOCK_STATUS" == *"Password locked"* ]]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: Service account '${CONF_USER}' is correctly locked."
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: Service account '${CONF_USER}' is not locked."
    echo -e "REMEDIATION: Lock the account using the passwd command: ${YELLOW}sudo passwd -l ${CONF_USER}${NC}"
  fi
 
  echo ""
}

# 2.2.3 Ensure the NGINX service account has an invalid shell
audit_2_2_3() {
  echo -e "${PURPLE}[2.2.3] Ensure the NGINX service account has an invalid shell${NC}"
  CONF_USER=$(sudo nginx -T 2>/dev/null | grep -i "^user" | awk '{print $2}' | sed 's/;//' | head -n 1)
  if [ -z "$CONF_USER" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: No NGINX user identified. Please check Task 2.2.1."
    return
  fi
  
  USER_SHELL=$(getent passwd "$CONF_USER" | cut -d: -f7)
  if [[ "$USER_SHELL" == *"/nologin"* ]] || [[ "$USER_SHELL" == *"/false"* ]]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: User '${CONF_USER}' is correctly restricted with an invalid shell ($USER_SHELL)."
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: User '${CONF_USER}' is using an interactive shell ($USER_SHELL)."
    echo "REMEDIATION: Change the login shell to /sbin/nologin:"
    echo -e " ${YELLOW}sudo usermod -s /sbin/nologin ${CONF_USER}${NC}"
  fi

  echo ""
}

# 2.3 Permissions and Ownership
# 2.3.1 Ensure NGINX directories and files are owned by root (Manual)
audit_2_3_1() {
  echo -e "${PURPLE}[2.3.1] Ensure NGINX directories and files are owned by root${NC}" 
  
  # Lay path cua file config nginx
  # Sau do, lay path cua thu muc cha chua file config do
  CONF_PATH=$(nginx -V 2>&1 | grep -oP '(?<=--conf-path=)[^ ]+')
  CONF_DIR=$(dirname "$CONF_PATH") 
  [ -z "$CONF_DIR" ] && CONF_DIR="/etc/nginx"

  # Kiem tra xem co file config nao khong thuoc so huu cua root:root khong
  FIND_OUTPUT=$(sudo find "$CONF_DIR" -name "*" \( -not -user root -o -not -group root \) -ls)

  if [ -z "$FIND_OUTPUT" ]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: All files and directories in $CONF_DIR are owned by root:root."
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: The following files have incorrect ownership:"
    echo -e " ${YELLOW}${FIND_OUTPUT}${NC}"
    
    echo "REMEDIATION: Set the ownership of the NGINX configuration directory to root:"
    echo -e " ${YELLOW}sudo chown -R root:root $CONF_DIR${NC}"
  fi

  echo ""
}

# 2.3.2 Ensure access to NGINX directories and files is restricted (Manual)
audit_2_3_2() {
  echo -e "${PURPLE}[2.3.2] Ensure access to NGINX directories and files is restricted${NC}"
  CONF_PATH=$(nginx -V 2>&1 | grep -oP '(?<=--conf-path=)[^ ]+')
  CONF_DIR=$(dirname "$CONF_PATH")
  [ -z "$CONF_DIR" ] && CONF_DIR="/etc/nginx"

  # Tim cac folder co quyen rong hon 700
  LOOSE_DIRS=$(sudo find "$CONF_DIR" -type d ! -perm 700)
  # Tim cac file co quyen rong hon 600 
  LOOSE_FILES=$(sudo find "$CONF_DIR" -type f ! -perm 600)

  if [ -z "$LOOSE_DIRS" ] && [ -z "$LOOSE_FILES" ]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: All NGINX directories and files have restricted permissions (700/600)."
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    [ -n "$LOOSE_DIRS" ] && echo -e "Loose directories:\n${YELLOW}${LOOSE_DIRS}${NC}"
    [ -n "$LOOSE_FILES" ] && echo -e "Loose files:\n${YELLOW}${LOOSE_FILES}${NC}"
    
    echo "REMEDIATION: Execute the following commands to restrict access to root only:"
    echo -e " ${YELLOW}sudo find $CONF_DIR -type d -exec chmod 700 {} +${NC}"
    echo -e " ${YELLOW}sudo find $CONF_DIR -type f -exec chmod 600 {} +${NC}"
  fi

  echo ""
}

# 2.3.3 Ensure the NGINX process ID (PID) file is secured (Manual)
audit_2_3_3() {
  echo -e "${PURPLE}[2.3.3] Ensure the NGINX process ID (PID) file is secured${NC}"

  # Tim path cua nginx pid file
  PID_PATH=$(nginx -V 2>&1 | grep -oP '(?<=--pid-path=)[^ ]+')
  [ -z "$PID_PATH" ] && PID_PATH="/run/nginx.pid"

  PID_INFO=$(stat -c "%U:%G %a" "$PID_PATH")
  PID_OWNER=$(echo "$PID_INFO" | awk '{print $1}')
  PID_PERM=$(echo "$PID_INFO" | awk '{print $2}')   
  
  if [ "$PID_OWNER" == "root:root" ] && [ "$PID_PERM" -le 644 ]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: PID file has correct ownership ($PID_OWNER) and permissions ($PID_PERM)."
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: PID file has insecure settings (Owner: $PID_OWNER, Perm: $PID_PERM)."
    echo "REMEDIATION: Set correct ownership and permissions for the PID file:"
    echo -e " ${YELLOW}sudo chown root:root $PID_PATH${NC}"
    echo -e " ${YELLOW}sudo chmod 644 $PID_PATH${NC}"
  fi

  echo ""
}

# 2.4 Network Configuration
# 2.4.1 Ensure NGINX only listens for network connections on authorized ports (Manual)
audit_2_4_1() {
  echo -e "${PURPLE}[2.4.1] Ensure NGINX only listens on authorized ports${NC}"
  
  LISTEN_CONF=$(sudo nginx -T 2>/dev/null | grep -i "listen" | grep -v "^ *#" | sort -u)
  if [ -z "$LISTEN_CONF" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: No active 'listen' directives found. NGINX might not be serving any traffic."
    return
  fi 

  UNAUTHORIZED=$(sudo netstat -tulpen | grep -i nginx | grep -vE ":80 |:443 ")
  if [ -z "$UNAUTHORIZED" ]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: NGINX is only listening on standard ports (80/443)."
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: NGINX is listening on potentially unauthorized ports:"
    echo -e "${RED}${UNAUTHORIZED}${NC}"

    echo -e "${BLUE}REMEDIATION:${NC}"
    echo " 1. Review the 'listen' directives above."
    echo " 2. Comment out (#) any ports like 8080, 8443 unless explicitly authorized."
    echo " 3. For HTTP/3, ensure UDP 443 is authorized."
  fi

  echo ""
}

# 2.4.2 Ensure requests for unknown host names are rejected (Manual)
audit_2_4_2() {
  echo -e "${PURPLE}[2.4.2] Ensure requests for unknown host names are rejected${NC}"
  
  # Lay cac thong tin cau hinh nginx
  CONF_DUMP=$(sudo nginx -T 2>/dev/null)
  
  HAS_DEFAULT=$(echo "$CONF_DUMP" | grep -v '^[[:space:]]*#' | grep -Ei "listen.*default_server")
  HAS_REJECT=$(echo "$CONF_DUMP" | grep -v '^[[:space:]]*#' | grep -Ei "return\s+(444|400|403|421)")
  HAS_SSL_REJECT=$(echo "$CONF_DUMP" | grep -v '^[[:space:]]*#' | grep -Ei "ssl_reject_handshake\s+on")
  
  if [ -z "$HAS_DEFAULT" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: No 'default_server' block detected. NGINX will serve the first site by default."
  elif [ -z "$HAS_REJECT" ] && [ -z "$HAS_SSL_REJECT" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: 'default_server' exists but lacks a rejection mechanism (return 444/4xx)."
  else
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: Catch-all mechanism is active. SSL Handshake rejection: Enabled."
    echo ""
    return 0 # return de khong in ra Remediation
  fi

  echo "REMEDIATION: Configure a 'Catch-All' block to prevent IP/Cert leakage:"
  echo -e "1. Create ${YELLOW}/etc/nginx/conf.d/00-default.conf${NC} with:"
  echo -e "   ${YELLOW}server {${NC}"
  echo -e "   ${YELLOW}    listen 80 default_server;${NC}"
  echo -e "   ${YELLOW}    listen 443 ssl default_server;${NC}"
  echo -e "   ${YELLOW}    ssl_reject_handshake on;  # Reject SSL Handshake for unknown domains${NC}"
  echo -e "   ${YELLOW}    server_name _;            # Catch-all name${NC}"
  echo -e "   ${YELLOW}    return 444;               # Silent drop${NC}"
  echo -e "   ${YELLOW}}${NC}"
  echo -e "2. Run: ${YELLOW}sudo nginx -t && sudo systemctl reload nginx${NC}"

  echo ""  
}

# 2.4.3 Ensure keepalive_timeout is 10 seconds or less, but not 0 (Manual)
audit_2_4_3() {
  echo -e "${PURPLE}[2.4.3] Ensure keepalive_timeout is set to 10 seconds or less, but not 0${NC}"

  # Tim gia tri keepalive_timeout trong file cau hinh nginx
  KEEPALIVE_VAL=$(sudo nginx -T 2>/dev/null | grep -i "keepalive_timeout" | awk '{print $2}' | tr -d ';' | head -n 1)
  
  if [ -n "$KEEPALIVE_VAL" ] && [ "$KEEPALIVE_VAL" -gt 0 ] && [ "$KEEPALIVE_VAL" -le 10 ]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: keepalive_timeout is correctly set to $KEEPALIVE_VAL seconds."
    echo ""
    return 0
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    if [ -z "$KEEPALIVE_VAL" ]; then
      echo "Detail: keepalive_timeout is not explicitly set."
    else
      echo "Detail: Current value '$KEEPALIVE_VAL' is out of the recommended range (1-10s)."
    fi
  fi

  echo "REMEDIATION:"
  echo " 1. Locate your NGINX configuration file (e.g., /etc/nginx/nginx.conf)."
  echo " 2. Add or update the 'keepalive_timeout' directive in the 'http' or 'server' block as follows:"
  echo -e "   ${YELLOW}keepalive_timeout 10;${NC}"
  echo " 3. Test the configuration for syntax errors:"
  echo -e "   ${YELLOW}sudo nginx -t${NC}"
  echo " 4. Reload the NGINX service to apply changes:"
  echo -e "   ${YELLOW}sudo systemctl reload nginx${NC}"

  echo ""
}

# 2.4.4 Ensure send_timeout is set to 10 seconds or less, but not 0 (Manual)
audit_2_4_4() {
  echo -e "${PURPLE}[2.4.4] Ensure send_timeout is set to 10 seconds or less, but not 0${NC}"

  # Lay gia tri send_timeout trong file cau hinh cua nginx 
  SEND_TIMEOUT_VAL=$(sudo nginx -T 2>/dev/null | grep -i "send_timeout" | awk '{print $2}' | tr -d ';' | head -n 1)

  if [ -n "$SEND_TIMEOUT_VAL" ] && [ "$SEND_TIMEOUT_VAL" -gt 0 ] && [ "$SEND_TIMEOUT_VAL" -le 10 ]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: send_timeout is correctly set to $SEND_TIMEOUT_VAL seconds."
    echo ""
    return 0
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    if [ -z "$SEND_TIMEOUT_VAL" ]; then
      echo "Detail: send_timeout is not explicitly set."
    else
      echo "Detail: Current value '$SEND_TIMEOUT_VAL' is out of the recommended range (1-10s)."
    fi
  fi

  echo "REMEDIATION:"
  echo " 1. Open your NGINX configuration file (e.g., /etc/nginx/nginx.conf)."
  echo " 2. Add or update the 'send_timeout' directive in the 'http' or 'server' block:"
  echo -e "    ${YELLOW}send_timeout 10;${NC}"
  echo " 3. Verify the configuration syntax:"
  echo -e "    ${YELLOW}sudo nginx -t${NC}"
  echo " 4. Reload NGINX to apply the new settings:"
  echo -e "    ${YELLOW}sudo systemctl reload nginx${NC}"

  echo ""
}

# 2.5 Information Disclosure
# 2.5.1 Ensure server_tokens directive is set to `off` (Manual)
audit_2_5_1() {
  echo -e "${PURPLE}[2.5.1] Ensure server_tokens directive is set to off${NC}"

  CONF_PATH=$(nginx -V 2>&1 | grep -oP '(?<=--conf-path=)[^ ]+')
  [ -z "$CONF_PATH" ] && CONF_PATH="/etc/nginx/nginx.conf"

  # Tim xem dong 'server_tokens off;' co trong file cau hinh cua nginx khong
  TOKENS_CONFIG=$(sudo grep -R "server_tokens" /etc/nginx 2>/dev/null | grep -v "#" | grep -w "off")

  SERVER_HEADER=$(curl -I -s http://localhost 2>/dev/null | grep -i "Server:")

  if [[ -n "$TOKENS_CONFIG" ]] && [[ ! "$SERVER_HEADER" =~ "/" ]]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: server_tokens is set to off. Server header: $SERVER_HEADER"
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: NGINX version is still visible in HTTP headers."
    echo -e " Current Header: ${YELLOW}${SERVER_HEADER}${NC}"
    echo "REMEDIATION: "
    echo -e " 1. Add 'server_tokens off;' to the http block in: ${YELLOW}$CONF_PATH${NC}"
    echo -e " 2. Test configuration: ${YELLOW}sudo nginx -t${NC}"
    echo -e " 3. Reload NGINX: ${YELLOW}sudo systemctl reload nginx${NC}"
  fi
  echo ""
}

# 2.5.2 Ensure default error and index.html pages do not reference NGINX (Manual)
audit_2_5_2() {
  echo -e "${PURPLE}[2.5.2] Ensure default error pages do not reference NGINX${NC}"

  # Kiem tra xem co error_page directive nao trong cau hinh cua nginx khong
  ERROR_PAGE_CONF=$(sudo nginx -T 2>/dev/null | grep -vE '^\s*#' | grep -i "error_page")
  if [ -z "$ERROR_PAGE_CONF" ]; then
    echo -e "STATUS: [${BLUE}INFO${NC}]"
    echo "Detail: No custom 'error_page' directives found. Using defaults."
    echo ""
  fi

  # Kiem tra chu 'nginx' co ton tai trong body tra ve cua loi 404 hay khong
  CHECK_404=$(curl -s http://localhost/non-existent-page-$(date +%s) | grep -io "nginx")
  
  if [ -z "$CHECK_404" ]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: No NGINX branding found in the error page body."
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: The error page still contains NGINX signatures/branding."
    echo "REMEDIATION:"
    echo " 1. Create custom generic HTML pages (e.g., /var/www/html/errors/404.html)."
    echo " 2. Add the following to your NGINX server block:"
    echo -e "    ${YELLOW}error_page 404 /404.html;${NC}"
    echo -e "    ${YELLOW}location = /404.html {${NC}"
    echo -e "    ${YELLOW}    root /var/www/html/errors;${NC}"
    echo -e "    ${YELLOW}    internal;${NC}"
    echo -e "    ${YELLOW}}${NC}"
  fi

  echo ""
}

# 2.5.3 Ensure hidden file serving is disabled (Manual)
audit_2_5_3() {
  echo -e "${PURPLE}[2.5.3] Ensure hidden file serving is disabled${NC}"  

  # Kiem tra xem co cau hinh quy tac chan file an nao chua
  HAS_RULE=$(sudo nginx -T 2>/dev/null | grep -vE '^\s*#'| grep -E "location\s+~\s+/\\\.")

  STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/.git/HEAD)

  if [[ -n "$HAS_RULE" && "$STATUS_CODE" =~ ^40[34]$ ]]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: Requests to hidden files are explicitly denied."
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: NGINX might serve hidden files."
    echo "REMEDIATION: Add this block to your server context:"
    echo -e "  ${YELLOW}# Allow Let's Encrypt (Must be before deny rule)${NC}"
    echo -e "  ${YELLOW}location ^~ /.well-known/acme-challenge/ { allow all; }${NC}"
    echo -e "  ${YELLOW}# Deny all other hidden files${NC}"
    echo -e "  ${YELLOW}location ~ /\. {${NC}"
    echo -e "  ${YELLOW}    deny all;${NC}"
    echo -e "  ${YELLOW}    return 404; ${NC}"
    echo -e "  ${YELLOW}}${NC}"
  fi

  echo ""
}

# 2.5.4 Ensure the NGINX reverse proxy does not enable information disclosure (Manual)
audit_2_5_4() {
  echo -e "${PURPLE}[2.5.4] Ensure NGINX reverse proxy hides backend headers${NC}"
  
  # Tim xem trong cau hinh cua nginx co lenh an header hay khong
  HIDE_CONF=$(sudo nginx -T 2>/dev/null | grep -vE '^\s*#' | grep -Ei "(proxy|fastcgi)_hide_header")

  HEADERS=$(curl -s -I http://localhost | grep -Ei "^(Server|X-Powered-By)")
  # Bad header la header khong bat dau bang 'Server: nginx'
  BAD_HEADERS=$(echo "$HEADERS" | grep -ivE "^Server: nginx")

  if [ -n "$HIDE_CONF" ] && [ -z "$BAD_HEADERS" ]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: Sensitive backend headers are suppressed."
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: Exposed backend headers detected:"
    echo -e "${YELLOW}${BAD_HEADERS}${NC}"
    echo "REMEDIATION: Add these directives to your 'location /' block:"
    echo -e "  ${YELLOW}proxy_hide_header X-Powered-By;${NC}"
    echo -e "  ${YELLOW}proxy_hide_header Server;${NC}"
    echo -e "If using PHP-FPM, use: ${YELLOW}fastcgi_hide_header X-Powered-By;${NC}"
  fi

  echo ""
}

# 3 Logging
# 3.1 Ensure detailed logging is enabled (Manual)
audit_3_1() {
  echo -e "${PURPLE}[3.1] Ensure detailed logging is enabled${NC}"

  NGINX_CONF=$(sudo nginx -T 2>/dev/null)
   
  # Lay log_format tu cau hinh cua nginx
  LOG_FORMAT=$(echo "$NGINX_CONF" | sed -n '/log_format/,/;/p')
 
  # Lay access_log (noi chua log va log su dung format nao)
  ACCESS_LOG=$(echo "$NGINX_CONF" | grep "access_log")

  if [ -z "$LOG_FORMAT" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]" 
    echo "Detail: No custom log_format defined."
    echo "REMEDIATION:"
    echo -e "${YELLOW}Add a detailed log_format in http block:${NC}"
    echo "log_format main '\$remote_addr - \$remote_user [\$time_iso8601] \"\$request\" \$status \"\$http_user_agent\"';"

    echo ""
    return
  fi 

  REQUIRED_FIELDS=("time_iso8601" "remote_user" "remote_addr" "request" "status" "http_user_agent")
  MISSING_FIELDS=()

  for field in "${REQUIRED_FIELDS[@]}"; do
    echo "$LOG_FORMAT" | grep -q "$field"
    if [ $? -ne 0 ]; then
      MISSING_FIELDS+=("$field")
    fi
  done 

  # Kiem tra xem access_log co su dung log_format nao khong
  FORMAT_USED=$(echo "$ACCESS_LOG" | awk '{print $3}')

  if [ -z "$FORMAT_USED" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: access_log is not using a custom format."
    echo "REMEDIATION:"
    echo -e "${YELLOW}Update access_log to use defined log_format:${NC}"
    echo "access_log /var/log/nginx/access.log main;"
    echo ""
    return
  fi

  if [ ${#MISSING_FIELDS[@]} -eq 0 ]; then
    echo -e "STATUS: [${GREEN}PASS${NC}]"
    echo "Detail: Logging has required fields."
  else
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: Missing required log fields:"
    for f in "${MISSING_FIELDS[@]}"; do
      echo -e "  ${YELLOW}$f${NC}"
    done
    
    echo "REMEDIATION: Update log_format to include missing fields (default location: /etc/nginx/nginx.conf):"
    echo -e "${YELLOW}  log_format main '\$remote_addr - \$remote_user [\$time_iso8601] \"\$request\" \$status \"\$http_user_agent\"';${NC}"
  fi
  
  echo ""
}

# 3.2 Ensure access logging is enabled (Manual)
audit_3_2() {
  echo -e "${PURPLE}[3.2] Ensure access logging is enabled${NC}"

  NGINX_CONF=$(sudo nginx -T 2>/dev/null)

  # Tim access_log trong file cau hinh Nginx
  ACCESS_LOG_LINES=$(echo "$NGINX_CONF" | grep -i "access_log")
  if [ -z "$ACCESS_LOG_LINES" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: No access_log directive found."
    echo "REMEDIATION:"
    echo -e "${YELLOW}Enable access logging in http block:${NC}"
    echo "access_log /var/log/nginx/access.log main;"

    echo ""
    return
  fi
  
  # Tim xem co 'access_log off' nao o global khong
  GLOBAL_OFF=$(echo "$NGINX_CONF" | grep -iE "http\s*{[^}]*access_log off" -z)
  # Tim xem trong cac server block co 'access_log off' nao khong
  SERVER_OFF=$(echo "$NGINX_CONF" | grep -iE "server\s*{[^}]*access_log off" -z)

  if [ -n "$GLOBAL_OFF" ] || [ -n "$SERVER_OFF" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: access_log is disabled in http/server block (critical)."
    echo "REMEDIATION:"
    echo -e "${YELLOW}Remove 'access_log off;' from global or server blocks.${NC}"
    echo -e "Use instead:"
    echo "access_log /var/log/nginx/access.log main;"

    echo ""
    return
  fi

  echo -e "STATUS: [${GREEN}PASS${NC}]"
  echo "Detail: access logging is properly enabled."

  echo ""
}

# 3.3 Ensure error logging is enabled and set to the info logging level (Manual)
audit_3_3() {
  echo -e "${PURPLE}[3.3] Ensure error logging is enabled and set to info level${NC}"
  
  NGINX_CONF=$(sudo nginx -T 2>/dev/null)

  # Tim 'error_log' trong file cau hinh cua Nginx
  ERROR_LOG_LINES=$(echo "$NGINX_CONF" | grep -i "error_log")

  if [ -z "$ERROR_LOG_LINES" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: No error_log directive found."
    echo "REMEDIATION:"
    echo -e "${YELLOW}Add error_log in main context:${NC}"
    echo "error_log /var/log/nginx/error.log notice;"

    echo ""
    return
  fi

  # Kiem tra xem dau ra cua error_log co phai /dev/null khong
  DEV_NULL=$(echo "$ERROR_LOG_LINES" | grep -i "/dev/null")

  if [ -n "$DEV_NULL" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: error_log is directed to /dev/null (logging disabled)."
    echo "REMEDIATION:"
    echo -e "${YELLOW}Update error_log to a valid file:${NC}"
    echo "error_log /var/log/nginx/error.log notice;"

    echo ""
    return
  fi

  # Kiem tra level cua cac error_log 
  BAD_LEVEL=$(echo "$ERROR_LOG_LINES" | grep -Ei "\b(emerg|alert|crit)\b")
  GOOD_LEVEL=$(echo "$ERROR_LOG_LINES" | grep -Ei "\b(info|notice)\b")

  if [ -n "$BAD_LEVEL" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: error_log level is too high (emerg/alert/crit), suppressing useful logs."
    echo "REMEDIATION:"
    echo -e "${YELLOW}Set log level to notice or info:${NC}"
    echo "error_log /var/log/nginx/error.log notice;"

    echo ""
    return
  fi

  # Kiem tra xem co error_log nao co level la error (default) khong 
  DEFAULT_LEVEL=$(echo "$ERROR_LOG_LINES" | grep -Ei "\berror\b")

  if [ -n "$DEFAULT_LEVEL" ] && [ -z "$GOOD_LEVEL" ]; then
    echo -e "STATUS: [${BLUE}INFO${NC}]"
    echo "Detail: error_log level is 'error' (default), may miss important events."
    echo "Recommendation: Use 'notice' or 'info' for better visibility."
  fi

  echo -e "STATUS: [${GREEN}PASS${NC}]"
  echo "Detail: error logging is properly configured with sufficient level."

  echo ""
}

# 3.4 Ensure proxies pass source IP information (Manual)
audit_3_4() {
  echo -e "${PURPLE}[3.4] Ensure proxies pass source IP information${NC}"

  NGINX_CONF=$(sudo nginx -T 2>/dev/null)

  # Kiem tra xem Nginx co duoc dung lam Proxy khong
  PROXY_PASS=$(echo "$NGINX_CONF" | grep -i "proxy_pass")

  if [ -z "$PROXY_PASS" ]; then
    echo -e "STATUS: [${BLUE}SKIP${NC}]"
    echo "Detail: No proxy_pass found (not acting as reverse proxy)."

    echo ""
    return
  fi

  # Lay cac header lien quan cua Proxy
  XFF=$(echo "$NGINX_CONF" | grep -i "proxy_set_header X-Forwarded-For")
  XREAL=$(echo "$NGINX_CONF" | grep -i "proxy_set_header X-Real-IP")

  if [ -z "$XFF" ] || [ -z "$XREAL" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: Missing required proxy headers."
    echo "REMEDIATION:"
    echo -e "${YELLOW}Add these headers in your proxy location:${NC}"
    echo "proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
    echo "proxy_set_header X-Real-IP \$remote_addr;"

    echo ""
    return
  fi

  # Check gia tri cua X-Forwarded-For co khac voi 2 gia tri ben duoi khong
  BAD_XFF=$(echo "$XFF" | grep -viP '\$proxy_add_x_forwarded_for|\$remote_addr')
  if [ -n "$BAD_XFF" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: X-Forwarded-For is not set correctly."
    echo "REMEDIATION:"
    echo -e "${YELLOW}Use one of the following:${NC}"
    echo "proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
    echo "or"
    echo "proxy_set_header X-Forwarded-For \$remote_addr;"

    echo ""
    return
  fi

  # Check xem gia tri cua X-Real-IP co khac voi gia tri ben duoi khong
  BAD_XREAL=$(echo "$XREAL" | grep -vi '\$remote_addr')
  if [ -n "$BAD_XREAL" ]; then
    echo -e "STATUS: [${RED}FAIL${NC}]"
    echo "Detail: X-Real-IP is not set to \$remote_addr."
    echo "REMEDIATION:"
    echo -e "${YELLOW}Set correct value:${NC}"
    echo "proxy_set_header X-Real-IP \$remote_addr;"

    echo ""
    return
  fi

  echo -e "STATUS: [${GREEN}PASS${NC}]"
  echo "Detail: Proxy headers are correctly configured."

  echo ""
}


# Goi cac ham audit
audit_1_1_1
audit_1_2_1
audit_1_2_2

audit_2_1_1

audit_2_2_1
audit_2_2_2
audit_2_2_3

audit_2_3_1
audit_2_3_2
audit_2_3_3

audit_2_4_1
audit_2_4_2
audit_2_4_3
audit_2_4_4

audit_2_5_1
audit_2_5_2
audit_2_5_3
audit_2_5_4

audit_3_1
audit_3_2
audit_3_3
audit_3_4
