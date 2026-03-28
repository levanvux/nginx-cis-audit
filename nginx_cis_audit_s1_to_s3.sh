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
  
  # Functional Test: gui req voi Host header gia mao den localhost
  TEST_RESULT=$(curl -s -I -H "Host: invalid.example.com" http://127.0.0.1 2>&1 | head -n 1)

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
