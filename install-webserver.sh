#!/bin/bash
NONE='\033[00m'
RED='\033[01;31m'
GREEN='\033[01;32m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
# =================== THIS SCRIPT  ========================
#bash <( curl -s https://raw.githubusercontent.com/thecrypt0hunter/web-installer/master/install-webserver.sh )

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
    apt-add-repository ppa:nginx/development -y &>> ${SCRIPT_LOGFILE}
    apt-add-repository ppa:ondrej/nginx -y &>> ${SCRIPT_LOGFILE}
    apt-add-repository ppa:chris-lea/redis-server -y &>> ${SCRIPT_LOGFILE}
    apt-add-repository ppa:certbot/certbot -y &>> ${SCRIPT_LOGFILE}
    apt update -qy &>> ${SCRIPT_LOGFILE} # Update Package Lists 
    # Install Base Packages
    apt install -qy build-essential curl fail2ban \
    gcc git libmcrypt4 libpcre3-dev python-certbot-nginx \
    make python2.7 python-pip supervisor ufw unattended-upgrades \
    unzip whois zsh mc p7zip-full htop ntp nano wget &>> ${SCRIPT_LOGFILE}
    echo -e "${GREEN}* Done${NONE}";
}

function disablePassAuth() {
    echo
    echo "* Disabling password authentication. Please wait..."
    # Disable Password Authentication Over SSH
    sed -i "/PasswordAuthentication yes/d" /etc/ssh/sshd_config
    echo "" | tee -a /etc/ssh/sshd_config  &>> ${SCRIPT_LOGFILE}
    echo "" | tee -a /etc/ssh/sshd_config  &>> ${SCRIPT_LOGFILE}
    echo "PasswordAuthentication no" | tee -a /etc/ssh/sshd_config  &>> ${SCRIPT_LOGFILE}
    # Restart SSH
    ssh-keygen -A
    service ssh restart
    echo -e "${GREEN}* Done${NONE}";
}

function setHostandTime() {
    echo
    echo "* Setting Host and timezone. Please wait..."
    # Set The Hostname If Necessary
    echo "${DNS_NAME}" > /etc/hostname
    sed -i "s/127\.0\.0\.1.*localhost/127.0.0.1	${DNS_NAME} localhost/" /etc/hosts
    hostname ${DNS_NAME}
    # Set The Timezone
    ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
    #timedatectl set-ntp no
    echo -e "${GREEN}* Done${NONE}";
}

function setupUser() {
    echo
    echo "* Setting up your user . Please wait..."
    # Create The Root SSH Directory If Necessary
    if [ ! -d /root/.ssh ]
        then
        mkdir -p /root/.ssh
        touch /root/.ssh/authorized_keys
    fi
    # Setup User
    useradd $USER &>> ${SCRIPT_LOGFILE}
    mkdir -p /home/$USER/.ssh
    adduser $USER sudo &>> ${SCRIPT_LOGFILE}
    # Setup Bash For User
    chsh -s /bin/bash $USER &>> ${SCRIPT_LOGFILE}
    cp /root/.profile /home/$USER/.profile &>> ${SCRIPT_LOGFILE}
    cp /root/.bashrc /home/$USER/.bashrc &>> ${SCRIPT_LOGFILE}
    # Set The Sudo Password For User
    PASSWORD=$(mkpasswd $SUDO_PASSWORD)
    usermod --password $PASSWORD $USER &>> ${SCRIPT_LOGFILE}
    # Build Formatted Keys & Copy Keys To User
cat > /root/.ssh/authorized_keys << EOF
$PUBLIC_SSH_KEYS 
EOF
    cp /root/.ssh/authorized_keys /home/$USER/.ssh/authorized_keys
    echo -e "${GREEN}* Done${NONE}";
}


function setupServerKeys() {
    echo
    echo "* Installing server keys. Please wait..."
    # Create The Server SSH Key
    ssh-keygen -f /home/$USER/.ssh/id_rsa -t rsa -N '' &>> ${SCRIPT_LOGFILE}
    # Copy Github And Bitbucket Public Keys Into Known Hosts File
    ssh-keyscan -H github.com >> /home/$USER/.ssh/known_hosts &>> ${SCRIPT_LOGFILE}
    ssh-keyscan -H bitbucket.org >> /home/$USER/.ssh/known_hosts &>> ${SCRIPT_LOGFILE}
    # Setup Site Directory Permissions
    chown -R $USER:$USER /home/$USER &>> ${SCRIPT_LOGFILE}
    chmod -R 755 /home/$USER &>> ${SCRIPT_LOGFILE}
    chmod 700 /home/$USER/.ssh/id_rsa &>> ${SCRIPT_LOGFILE}
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

function installDotNetCore() {
    echo
    echo -e "* Installing .Net Core. Please wait..."
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${VERSION_ID}" = "16.04" ]]; then
            wget -q https://packages.microsoft.com/config/ubuntu/16.04/packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            dpkg -i packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            apt install apt-transport-https -y &>> ${SCRIPT_LOGFILE}
            apt update -y &>> ${SCRIPT_LOGFILE}
            apt install dotnet-sdk-2.2 -y &>> ${SCRIPT_LOGFILE}
            echo -e "${NONE}${GREEN}* Done${NONE}";
        fi
        if [[ "${VERSION_ID}" = "18.04" ]]; then
            wget -q https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            dpkg -i packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            add-apt-repository universe -y &>> ${SCRIPT_LOGFILE}
            apt install apt-transport-https -y &>> ${SCRIPT_LOGFILE}
            apt update -y &>> ${SCRIPT_LOGFILE}
            apt install dotnet-sdk-2.2 -y &>> ${SCRIPT_LOGFILE}
            echo -e "${NONE}${GREEN}* Done${NONE}";
        fi
        if [[ "${VERSION_ID}" = "19.04" ]]; then
            wget -q https://packages.microsoft.com/config/ubuntu/19.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            dpkg -i packages-microsoft-prod.deb &>> ${SCRIPT_LOGFILE}
            apt install apt-transport-https -y &>> ${SCRIPT_LOGFILE}
            apt update -y &>> ${SCRIPT_LOGFILE}
            apt install dotnet-sdk-2.2 -y &>> ${SCRIPT_LOGFILE}
            wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl1.0/libssl1.0.0_1.0.2n-1ubuntu6_amd64.deb &>> ${SCRIPT_LOGFILE}
            dpkg -i libssl1.0.0_1.0.2n-1ubuntu6_amd64.deb &>> ${SCRIPT_LOGFILE}
            echo -e "${NONE}${GREEN}* Done${NONE}";
        fi
        if [[ "${VERSION_ID}" = "9" ]]; then ## Placeholder for Debian
            echo -e "${NONE}${GREEN}* Done${NONE}";
        fi
        else
        echo -e "${NONE}${RED}* Version: ${VERSION_ID} not supported.${NONE}";
    fi
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
        proxy_pass         http://localhost:${PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection keep-alive;
        proxy_set_header   Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
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

function installPostgres() {
    echo
    echo "* Installing Postgres. Please wait..."
    apt install ca-certificates &>> ${SCRIPT_LOGFILE}
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - &>> ${SCRIPT_LOGFILE}
    sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" >> /etc/apt/sources.list.d/pgdg.list' &>> ${SCRIPT_LOGFILE}
    apt update -y &>> ${SCRIPT_LOGFILE}
    apt -qy install postgresql postgresql-contrib &>> ${SCRIPT_LOGFILE}
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

function installRedis() {
    echo
    echo "* Installing Redis. Please wait..."
    apt -qy install redis-server &>> ${SCRIPT_LOGFILE}
    sed -i 's/bind 127.0.0.1/bind 0.0.0.0/' /etc/redis/redis.conf
    service redis-server restart  &>> ${SCRIPT_LOGFILE}
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

function installMemcached() {
    echo
    echo "* Installing Memcached. Please wait..."
    # Install & Configure Memcached
    apt -qy install memcached  &>> ${SCRIPT_LOGFILE}
    sed -i 's/-l 127.0.0.1/-l 0.0.0.0/' /etc/memcached.conf
    service memcached restart  &>> ${SCRIPT_LOGFILE}
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

function installBeanstalk() {
    echo
    echo "* Installing Beanstalk. Please wait..."
    # Install & Configure Beanstalk
    apt -qy install beanstalkd  &>> ${SCRIPT_LOGFILE}
    sed -i "s/BEANSTALKD_LISTEN_ADDR.*/BEANSTALKD_LISTEN_ADDR=0.0.0.0/" /etc/default/beanstalkd
    sed -i "s/#START=yes/START=yes/" /etc/default/beanstalkd
    /etc/init.d/beanstalkd start  &>> ${SCRIPT_LOGFILE}
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

function compileWebsite() {
    echo
    echo "* Installing your website from ${WEBFILE} into /home/${USER}/${DNS_NAME}. Please wait..."
    mkdir /home/${USER}/${DNS_NAME}  &>> ${SCRIPT_LOGFILE}
    cd /home/${USER}/
    git clone --recurse-submodules ${WEBFILE} code &>> ${SCRIPT_LOGFILE}  ## --branch=${BRANCH}
    cd /home/${USER}/code
    git submodule update --init --recursive &>> ${SCRIPT_LOGFILE}
    cd ${GITROOT}
    dotnet publish -c ${CONF} -r ${ARCH} -v m -o /home/${USER}/${DNS_NAME} &>> ${SCRIPT_LOGFILE} ### compile & publish code
    rm -rf /home/${USER}/code &>> ${SCRIPT_LOGFILE} 	                                     ### Remove source
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

function setupWebService() {
    echo
    echo -e "* Setup Website as a service. Please wait..."
    cd /home/${USER}/
    cat >/home/${USER}/${DNS_NAME}/run.sh << EOF
#!/bin/bash
export DOTNET_CLI_TELEMETRY_OPTOUT=1
cd /home/${USER}/${DNS_NAME}
dotnet ${APP_NAME}.dll
EOF

    cat > /etc/systemd/system/${APP_NAME}.service << EOF
[Unit]
Description=${DNS_NAME}
After=network-online.target
[Service]
Type=simple
User=${USER}
WorkingDirectory=/home/${USER}/${DNS_NAME}
ExecStart=/home/${USER}/${DNS_NAME}/run.sh
Restart=always
RestartSec=10
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=5s
StartLimitInterval=120s
StartLimitBurst=15
KillSignal=SIGINT
SyslogIdentifier=${USER}
Environment=ASPNETCORE_ENVIRONMENT=Production
Environment=DOTNET_PRINT_TELEMETRY_MESSAGE=false
[Install]
WantedBy=multi-user.target
EOF
    chown -R ${USER}:${USER} /etc/systemd/system/${APP_NAME}.service &>> ${SCRIPT_LOGFILE}
    sudo chmod 777 /home/${USER}/${DNS_NAME}/run.sh &>> ${SCRIPT_LOGFILE}
    sudo systemctl --system daemon-reload &>> ${SCRIPT_LOGFILE}
    sudo systemctl enable ${APP_NAME}.service &>> ${SCRIPT_LOGFILE}
    echo -e "${NONE}${GREEN}* Done${NONE}";
}

function startWebService() {
    echo
    echo -e "* Starting ${DNS_NAME}.service"
    sudo service ${DNS_NAME}.service start &>> ${SCRIPT_LOGFILE}
    sleep 2
    echo -e "${GREEN}* Done${NONE}";
}
function stopWebService() {
    echo
    echo -e "* Stopping ${DNS_NAME}.service"
    sudo service ${DNS_NAME}.service stop &>> ${SCRIPT_LOGFILE}
    sleep 2
    echo -e "${GREEN}* Done${NONE}";
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
    echo -e "${GREEN}Website location: ${NONE}/home/"${USER}/${DNS_NAME}
    echo -e "${GREEN}Sudo password for ${USER}: ${NONE}"${SUDO_PASSWORD}
    echo -e "${GREEN}Server Blocks: ${NONE}/etc/nginx/sites-enabled/"
    echo && echo
    echo -e "${UNDERLINE}${BOLD}Installation details${NONE}"
    echo -e "${GREEN}"
    nginx -v
    echo -e "${NONE}"
    dotnet --info
    echo -e "${GREEN}"
    sudo -u postgres psql -V
    echo -e "${NONE}"
    if systemctl is-active --quiet ${DNS_NAME}.service; then echo -e "${DNS_NAME} Service: ${on}"; else echo -e "${DNS_NAME} Service: ${off}"; fi
    echo
    if systemctl is-active --quiet redis-server; then echo -e "Redis Service: ${on}"; else echo -e "Redis Service: ${off}"; fi
	echo
    if systemctl is-active --quiet beanstalkd; then echo -e "Beanstalk Service: ${on}"; else echo -e "Beanstalk Service: ${off}"; fi
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

# ========================= PLAN ===========================

clear
echo -e "${UNDERLINE}${BOLD}Web Server Installation Guide${NONE}"
echo
read -p "Before you continue ensure that your DNS has an 'A' record for $(curl --silent ipinfo.io/ip) - press any key to continue" response
echo
read -p "What is the domain name for the website? " DNS_NAME
read -p "Admin email address for SSL Cert? " EMAIL
read -p "What is the GIT url for your website? " WEBFILE
read -p "What port is your .Net application designed to work on (default=5000)" PORT
if [${PORT} = ""]; then PORT="5000"; fi
read -p "What is your web root folder? " GITROOT
read -p "What is the name of your .Net application?" APP_NAME
read -p "What user name do you want to use? " USER
echo "Add your SSH public key here: "
read -p "" PUBLIC_SSH_KEYS
echo
# =================== SOME SETTINGS ========================

ARCH="linux-x64"
CONF="release"
OS_VER="Ubuntu*" ## or "Debian*"
SERVER_IP=$(curl --silent ipinfo.io/ip) ## Grabs the public IP address of the server
SUDO_PASSWORD=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1` ## sets a random password
SWAP_SIZE="1G" # swap file size create it
TIMEZONE="Etc/GMT+0" # list of avaiable timezones: ls -R --group-directories-first /usr/share/zoneinfo
DATE_STAMP="$(date +%y-%m-%d-%s)"
SCRIPT_LOGFILE="/tmp/${USER}_${DATE_STAMP}_output.log"

# ======================= EXECUTION =======================

checkRoot
checkOS
updateOS
InstallRepos
disablePassAuth
setHostandTime
setupUser
setupServerKeys
setupUpdates
setupFirewall
configSupervisor
setupSwap
installFail2Ban
installDotNetCore
installNginx
installPostgres
installRedis
installMemcached
installBeanstalk
compileWebsite
setupWebService
startWebService
installSSLCert
displayInfo