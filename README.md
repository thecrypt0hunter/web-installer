# Web Server Installer

Installs and configures 
- a Nginx Web Server
- .Net Core
- Postgres DB
- Redis
- Memcached
- Beanstalk 
- a website of your choice from Github
- with an SSL certificate from Let's Encrypt

Best using a freshly installed Ubuntu OS (16.04 - 19.04).

Have the following information at hand:

- The domain name for your website
- Admin email address for SSL Cert
- the GIT url for your website
- A username for your server
- Your SSH public key

Run the following command as root `sudo su`:

`bash <( curl -s https://raw.githubusercontent.com/thecrypt0hunter/web-installer/master/install-webserver.sh )`


