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
}

audit_1_1_1
