#!/bin/bash
NONE='\033[00m'
RED='\033[01;31m'
GREEN='\033[01;32m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
# =================== THIS SCRIPT  ========================
#bash <( curl -s https://raw.githubusercontent.com/thecrypt0hunter/web-installer/master/install-reverse-proxy.sh )

# ===================== FUNCTIONS ======================

function checkRoot {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}* Sorry, this script needs to be run as root. Do \"sudo su root\" and then re-run this script${NONE}"
        exit 1
        echo -e "${NONE}${GREEN}* All Good!${NONE}";
    fi
}

function checkOS() {
   echo
   echo "* Checking OS version..."
    if [[ `cat /etc/issue.net`  == ${OS_VER} ]]; then
        echo -e "${GREEN}* You are running `cat /etc/issue.net` . Setup will continue.${NONE}";
    else
        echo -e "${RED}* You are not running ${OS_VER}. You are running `cat /etc/issue.net` ${NONE}";
        echo && echo "Installation cancelled" && echo;
        exit;
    fi
}

function updateOS() {
    echo
    echo "* Running update and upgrade. Please wait..."
    # Prefer IPv4 over IPv6 - make apt faster
    sed -i "s/#precedence ::ffff:0:0\/96  100/precedence ::ffff:0:0\/96  100/" /etc/gai.conf
    DEBIAN_FRONTEND=noninteractive apt update -qq -y &>> ${SCRIPT_LOGFILE}
    DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq &>> ${SCRIPT_LOGFILE}
    DEBIAN_FRONTEND=noninteractive apt autoremove -y -qq &>> ${SCRIPT_LOGFILE}
    echo -e "${GREEN}* Done${NONE}";
}

function InstallRepos() {
    echo
    echo "* Installing some repo's and base packages. Please wait..."
    # Add A Few PPAs To Stay Current
    apt -qy install software-properties-common &>> ${SCRIPT_LOGFILE}
#    apt-add-repository ppa:nginx/development -y &>> ${SCRIPT_LOGFILE}
#    apt-add-repository ppa:ondrej/nginx -y &>> ${SCRIPT_LOGFILE}
#    apt-add-repository ppa:certbot/certbot -y &>> ${SCRIPT_LOGFILE}
    apt update -qy &>> ${SCRIPT_LOGFILE} # Update Package Lists 
    # Install Base Packages
    apt install -qy build-essential curl fail2ban \
    gcc git libmcrypt4 libpcre3-dev python-certbot-nginx \
    make python2.7 python-pip supervisor ufw unattended-upgrades \
    unzip whois zsh mc p7zip-full htop ntp nano wget &>> ${SCRIPT_LOGFILE}
    echo -e "${GREEN}* Done${NONE}";
}

function setupUpdates() {
    echo
    echo "* Setup unattended updates. Please wait..."
    # Setup Unattended Security Upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "Ubuntu xenial-security";
};
Unattended-Upgrade::Package-Blacklist {
    //
};
EOF
    cat > /etc/apt/apt.conf.d/10periodic << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
    echo -e "${GREEN}* Done${NONE}";
}

function setupFirewall() {
    echo
    echo "* Configuring firewall. Please wait..."
    # Setup UFW Firewall
    ufw allow 22 &>> ${SCRIPT_LOGFILE}
    ufw allow 'Nginx Full' &>> ${SCRIPT_LOGFILE}
    ufw --force enable &>> ${SCRIPT_LOGFILE}
    echo -e "${GREEN}* Done${NONE}";
}

function configSupervisor() {
    echo
    echo "* Enabling supervisor. Please wait..."
    # Configure Supervisor Autostart
    systemctl enable supervisor.service &>> ${SCRIPT_LOGFILE}
    service supervisor start &>> ${SCRIPT_LOGFILE}
    echo -e "${GREEN}* Done${NONE}";
}

function setupSwap() {
    echo
    echo "* Checking and installing swap file. Please wait..."
    # Configure Swap Disk
    if [ -f /var/node_swap.img ]; then
        echo "Swap exists."
    else
        fallocate -l $SWAP_SIZE /var/node_swap.img &>> ${SCRIPT_LOGFILE}
        chmod 600 /var/node_swap.img &>> ${SCRIPT_LOGFILE}
        mkswap /var/node_swap.img &>> ${SCRIPT_LOGFILE}
        swapon /var/node_swap.img &>> ${SCRIPT_LOGFILE}
        echo "/var/node_swap.img none swap sw 0 0" >> /etc/fstab
        echo "vm.swappiness=30" >> /etc/sysctl.conf
        echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.conf
    fi
    echo -e "${GREEN}* Done${NONE}";
}

function installFail2Ban() {
    echo
    echo -e "* Installing fail2ban. Please wait..."
    apt -y install fail2ban &>> ${SCRIPT_LOGFILE}
    systemctl enable fail2ban &>> ${SCRIPT_LOGFILE}
    systemctl start fail2ban &>> ${SCRIPT_LOGFILE}
    # Add Fail2Ban memory hack if needed
    if ! grep -q "ulimit -s 256" /etc/default/fail2ban; then
       echo "ulimit -s 256" | tee -a /etc/default/fail2ban &>> ${SCRIPT_LOGFILE}
       systemctl restart fail2ban &>> ${SCRIPT_LOGFILE}
    fi
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

function installNginx() {
    echo
    echo "* Installing Nginx. Please wait..."
    # Install Nginx & PHP-FPM
    apt install -qy nginx &>> ${SCRIPT_LOGFILE}
    # Enable Nginx service
    systemctl enable nginx.service &>> ${SCRIPT_LOGFILE}
    # Generate dhparam File
    openssl dhparam -out /etc/nginx/dhparams.pem 2048 &>> ${SCRIPT_LOGFILE}
    # Disable The Default Nginx Site
    rm /etc/nginx/sites-enabled/default &>> ${SCRIPT_LOGFILE}
    rm /etc/nginx/sites-available/default &>> ${SCRIPT_LOGFILE}
    service nginx restart &>> ${SCRIPT_LOGFILE}
    # Configure Nginx To Run As User
    sed -i "s/user www-data;/user $USER;/" /etc/nginx/nginx.conf
    sed -i "s/# DNS_NAMEs_hash_bucket_size.*/DNS_NAMEs_hash_bucket_size 64;/" /etc/nginx/nginx.conf
    # Configure A Few More Server Things
    sed -i "s/worker_processes.*/worker_processes auto;/" /etc/nginx/nginx.conf
    sed -i "s/# multi_accept.*/multi_accept on;/" /etc/nginx/nginx.conf
    # Install A Catch All Server
    cat > /etc/nginx/sites-available/catch-all << EOF
server {
    return 404;
}
EOF
    ln -s /etc/nginx/sites-available/catch-all /etc/nginx/sites-enabled/catch-all
    cat > /etc/nginx/sites-available/${DNS_NAME} << EOF
server {
    listen        80;
    server_name ${DNS_NAME};

    location / {
        proxy_pass                          http://DESTINATION_IP;
        proxy_http_version                  1.1;
        proxy_set_header Upgrade            \$http_upgrade;
        proxy_set_header                    Connection keep-alive;
        proxy_set_header Host               \$host;
        proxy_cache_bypass                  \$http_upgrade;
        proxy_set_header X-Real-IP          \$remote_addr;
        proxy_set_header X-Forwarded-For    \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto  \$scheme;
        proxy_set_header Connection         "upgrade";
        proxy_set_header X-Forwarded-Host   \$host;
        proxy_set_header X-Forwarded-Port   \$server_port;
    }
}
EOF

    ln -s /etc/nginx/sites-available/${DNS_NAME} /etc/nginx/sites-enabled/${DNS_NAME} &>> ${SCRIPT_LOGFILE}
    # Restart Nginx Service
    service nginx restart &>> ${SCRIPT_LOGFILE}
    service nginx reload &>> ${SCRIPT_LOGFILE}
    # Add User To www-data Group
    usermod -a -G www-data $USER &>> ${SCRIPT_LOGFILE}
    id $USER &>> ${SCRIPT_LOGFILE}
    groups $USER &>> ${SCRIPT_LOGFILE}
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

function installSSLCert() {
    echo
    echo "* Fetching and installing your SSL Certificate. Please wait..."
    # Install SSL certificate if using DNS
    certbot --nginx \
    --non-interactive \
    --agree-tos \
    --email ${EMAIL} \
    --domains ${DNS_NAME} &>> ${SCRIPT_LOGFILE}
    echo -e "${NONE}${GREEN}* Done${NONE}";
}


function displayInfo() {
    # Display information
	on="${GREEN}ACTIVE${NONE}"
	off="${RED}OFFLINE${NONE}"
    echo
    echo -e "${UNDERLINE}${BOLD}Important information${NONE}"
    echo
    echo -e "${GREEN}Installation logs: ${NONE}"${SCRIPT_LOGFILE}
    echo -e "${GREEN}Website URL: ${NONE}"${DNS_NAME}
    echo -e "${GREEN}External IP address for DNS: ${NONE}"${SERVER_IP}
    echo -e "${GREEN}Destination IP address: ${NONE}"${DESTINATION_IP}
    echo -e "${GREEN}Server Blocks: ${NONE}/etc/nginx/sites-enabled/"
    echo && echo
    echo -e "${UNDERLINE}${BOLD}Installation details${NONE}"
    echo -e "${GREEN}"
    nginx -v
    echo
    echo -e "${UNDERLINE}${BOLD}Running a simulation for SSL renewal${NONE}"
    echo 
    certbot renew --dry-run
    echo && echo
    echo "If the dry run was unsuccessful you may need to register & install your SSL certificate manually by running the following command: "
    echo
    echo "certbot --nginx --non-interactive --agree-tos --email ${EMAIL} --domains ${DNS_NAME}"
    echo
}

# =================== SOME SETTINGS ========================

OS_VER="Debian*" ## or "Ubuntu*"
SERVER_IP=$(curl --silent ipinfo.io/ip) ## Grabs the public IP address of the server
SWAP_SIZE="1G" # swap file size create it
DATE_STAMP="$(date +%y-%m-%d-%s)"
SCRIPT_LOGFILE="/tmp/${USER}_${DATE_STAMP}_output.log"

# ========================= PLAN ===========================

clear
echo -e "${UNDERLINE}${BOLD}Reverse Proxy Installation Guide${NONE}"
echo
read -p "Before you continue ensure that your DNS has an 'A' record for ${SERVER_IP} - press any key to continue" response
echo
read -p "What is the domain name for the website? " DNS_NAME
read -p "Admin email address for SSL Cert? " EMAIL
read -p "What is the IP of the destination server? " DESTINATION_IP
echo

# ======================= EXECUTION =======================

checkRoot
checkOS
updateOS
InstallRepos
setupUpdates
setupFirewall
configSupervisor
#setupSwap
installFail2Ban
installNginx
installSSLCert
displayInfo