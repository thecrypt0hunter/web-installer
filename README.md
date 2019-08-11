# Web Server Installer

Works best when using a freshly installed Ubuntu OS (16.04 - 19.04).

This script will install and configure:

- a Nginx Web Server
- .Net Core
- Postgres DB
- Redis
- Memcached
- Beanstalk 
- a website of your choice from Github
- with an SSL certificate from Let's Encrypt

Before you continue ensure that your DNS has an 'A' record for the servers IP address otherwise there will be problems with the SSL certificate and you will need to configure manually.

Have the following information at hand:

- The domain name for your website
- Admin email address for SSL Cert
- the GIT url for your website
- A username for your server
- Your SSH public key

Run the following command as root `sudo su`:

`bash <( curl -s https://raw.githubusercontent.com/thecrypt0hunter/web-installer/master/install-webserver.sh )`

To register & install your SSL certificate manually run the following command:

`certbot --nginx \`
`--non-interactive \`
`--agree-tos \`
`--email {EMAIL} \`
`--domains {DNS_NAME}`