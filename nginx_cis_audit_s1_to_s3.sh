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

audit_1_1_1
audit_1_2_1
audit_1_2_2
