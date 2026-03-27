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
#audit_2_2_1() {
 
#}


audit_1_1_1
audit_1_2_1
audit_1_2_2
audit_2_1_1
