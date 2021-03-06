#!/bin/sh

STARTDIR=`pwd`
# Basic infrastructure - these are already in CentOS 7 Vagrant from McCode
# apt-get -y install net-tools iproute2 sudo openssh-server xbase-clients zip unzip

# Add nonfree and contrib repo
#sed -i.bak s/main/main\ contrib\ non-free/g /etc/apt/sources.list
#apt-get update

# Add mccode repo
cd /etc/yum.repos.d/
rm mccode.repo
wget http://packages.mccode.org/rpm/mccode.repo
yum update

# Base packages for McCode + MPI
yum -y install mcstas-suite-perl mcstas-suite-python mcxtrace-suite-perl openmpi openmpi-devel
ln -sf /usr/lib64/openmpi/bin/mpirun /usr/local/bin
ln -sf /usr/lib64/openmpi/bin/mpicc /usr/local/bin

#mcxtrace-suite-python requires python3-matplotlib, would be fixed with new McXtrace release

# MySQL
#echo "deb http://repo.mysql.com/apt/debian/ stretch mysql-5.7" > /etc/apt/sources.list.d/mysql.list
#echo "deb-src http://repo.mysql.com/apt/debian/ stretch mysql-5.7" >> /etc/apt/sources.list.d/mysql.list
#wget -O /tmp/RPM-GPG-KEY-mysql https://repo.mysql.com/RPM-GPG-KEY-mysql
#apt-key add /tmp/RPM-GPG-KEY-mysql
#apt-get update
#apt-get -y install mysql-server mysql-client
cd $STARTDIR
yum -y install mariadb postgresql postgresql-server
#mysql-server mysql-client
sudo postgresql-setup initdb
sudo systemctl start postgresql
sudo systemctl enable postgresql

#OK:
#echo
#echo
#echo -n Please enter your mysql root password and press [ENTER]:
#read MYSQL_PASS
#export MYSQL_PASS

#echo
#echo
#echo -n Please enter your wanted PostgreSQL 'wikiuser' access password and press [ENTER]:
#read PGSQL_PASS
#export PGSQL_PASS

# Postgresql 
#apt-get -y install postgresql php-pgsql
cd /tmp

#OK:
#sudo -u postgres -H -- psql -d template1 -c "create user wikiuser with password '$PGSQL_PASS';"
#sudo -u postgres -H -- psql -d template1 -c "create database my_wiki;"
#sudo -u postgres -H -- psql -d template1 -c "GRANT ALL PRIVILEGES ON DATABASE my_wiki to wikiuser;"

# Mediawiki-dependency... Unfortunately we can currently not follow Debian here... :-(
#apt-get -y install php-apcu

# Remove stop apache2 from being default webserver
#update-rc.d apache2 remove
#service apache2 stop

rpm -Uvh https://mirror.webtatic.com/yum/el7/webtatic-release.rpm

# Packages for boo…tstrapping an McWeb instance
yum -y install php70w git python-devel openssl-devel python-virtualenv expect nginx php70w-fpm php70w-mysql php70w-xml php70w-curl php70w-zip php70w-gd php70w-mbstring php70w-xmlrpc php70w-soap php70w-intl php70w-ldap openldap compat-openldap openldap-clients openldap-servers openldap-servers-sql openldap-devel
#libsasl2-dev


sudo systemctl start nginx

rm -rf /srv/mcweb
mkdir /srv/mcweb
mkdir -p /srv/moodledata
mkdir -p /srv/moodledata/repository
mkdir -p /srv/moodledata/repository/uploads
mkdir -p /srv/mcweb/moodle-course-templates
mkdir -p /srv/mcweb/moodle-restore-jobs
mkdir -p /srv/mcweb/moodle-fullbackups
sudo chown -R nginx:nginx /srv/mcweb /srv/moodledata 
# Directory for Moodle filesystem access, group right nginx 
sudo chmod g+w /srv/moodledata/repository/uploads

# Bootstrap McWeb via sudo / git
cd /srv/mcweb
sudo -u nginx -H virtualenv mcvenv
sudo -u nginx cp mcvenv/bin/activate mcvenv_finishup
echo pip install -I Django==1.8.2 >> mcvenv_finishup
echo pip install -I django-auth-ldap==1.2.7 >> mcvenv_finishup
echo pip install simplejson uwsgi python-ldap >> mcvenv_finishup
sudo -u nginx bash mcvenv_finishup

sudo -u nginx git clone https://github.com/McStasMcXtrace/McWeb

# Pick and pull the STABLE branch
cd McWeb
sudo -u nginx git checkout MCWEB_STABLE_2.0
sudo -u nginx git pull

# Moodle
cd /srv/mcweb
sudo -u nginx git clone https://github.com/moodle/moodle.git
cd moodle
sudo -u nginx git checkout `cat ../McWeb/scripts/MOODLE_PREFERRED_VERSION `
cd /srv/mcweb
sudo -u nginx cp McWeb/bootstrap_data/moodle/* /srv/mcweb/moodle-course-templates/

# Moosh
cd /srv/mcweb
sudo -u nginx git clone https://github.com/tmuras/moosh.git
cd moosh
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php -r "if (hash_file('sha384', 'composer-setup.php') === '48e3236262b34d30969dca3c37281b3b4bbe3221bda826ac6a9a62d6444cdb0dcd0615698a5cbe587c3f0fe57a54d8f5') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
php composer-setup.php
php -r "unlink('composer-setup.php');"
php composer.phar install
ln -sf $PWD/moosh.php /usr/local/bin/moosh

# Mediawiki 1.26.4...
cd /srv/mcweb
sudo -u nginx git clone https://gerrit.wikimedia.org/r/p/mediawiki/core.git mediawiki
sudo -u nginx ln -s mediawiki wiki
cd mediawiki
#sudo -u nginx git checkout 1.26.4
sudo -u nginx php ../moosh/composer.phar install --no-dev

# Mathjax for use with mediawiki
cd /srv/mcweb
sudo tar xzf /srv/mcweb/McWeb/other/mathjax.tgz

cd /srv/mcweb
ln -sf /srv/mcweb/McWeb/scripts/uwsgi_mcweb /etc/init.d/uwsgi_mcweb
sudo chkconfig --add uwsgi_mcweb

# Install and configure LDAP
#apt-get -y install slapd ldap-utils
echo
echo
echo -n Please enter your LDAP admin password and press [ENTER]:
read LDAP_PASS
LDAPDOMAIN=`slapcat |grep dn:\ dc|cut -f2- -d\ `
LDAPADMIN=`slapcat |grep admin | grep dn:\ cn=admin | cut -f2- -d\ `
LDAPGRP=`slapcat |grep ^dn | grep dn:\ ou=users | cut -f2- -d\ `
export LDAP_PASS
export LDAPADMIN
export LDAPDOMAIN
export LDAPGRP
IPADDR=`ip addr show | grep inet\ | cut -f 2 -d\t | cut -f 1 -d/ |grep -v 127 | sed "s/\ //g"`
SERVERNAME=`hostname`
export IPADDR
export SERVERNAME
# Increase search limit to 50000 in ldap:
ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f /srv/mcweb/McWeb/scripts/changesize.ldif

echo -n Please enter your Django upload password and press [ENTER]:
read UPLOADPW
export UPLOADPW

echo -n Please enter desired simulator MPI cores pr. sim job press [ENTER]:
read MPICORES
export MPICORES

# Allow nginx to restart uwsgi
echo >> /etc/sudoers
echo "# Allow nginx to restart uwsgi_mcweb service" >> /etc/sudoers
echo "nginx ALL = NOPASSWD: /etc/init.d/uwsgi_mcweb" >> /etc/sudoers

# Last setup of uwsgi etc
echo Resuming setup...
sed "s/dc=risoe,dc=dk/${LDAPDOMAIN}/g" /srv/mcweb/McWeb/mcsimrunner/mcweb/settings.py.in > /srv/mcweb/McWeb/mcsimrunner/mcweb/settings.py
sed -i "s/@LDAP_PW@/${LDAP_PASS}/g" /srv/mcweb/McWeb/mcsimrunner/mcweb/settings.py 
sed -i "s/@IPADDR@/${IPADDR}/g" /srv/mcweb/McWeb/mcsimrunner/mcweb/settings.py 
sed -i "s/@SERVERNAME@/${SERVERNAME}/g" /srv/mcweb/McWeb/mcsimrunner/mcweb/settings.py 
sed -i "s/@UPLOADPW@/${UPLOADPW}/g" /srv/mcweb/McWeb/mcsimrunner/mcweb/settings.py
sed -i "s/@MPICORES@/${MPICORES}/g" /srv/mcweb/McWeb/mcsimrunner/mcweb/settings.py

# Install piwik
cd /tmp/
wget https://builds.piwik.org/piwik.zip
cd /srv/mcweb/
sudo -u nginx unzip /tmp/piwik.zip

cd $STARTDIR
# Check if we were givern a mediawiki archive as a $1
if [ -n "$1" ]; then
    if [ -d "$1" ]; then
	echo Attempting to restore mediawiki archive from $1
	BACKUPDIR=`basename $1`
	cd `dirname $1`
	/srv/mcweb/McWeb/scripts/mediawiki-backup/restore_all.sh $BACKUPDIR
        # Now configure the LocalSettings script from the backup for our new system
	cd $STARTDIR
	cd $1
	# LDAP first
	echo Setting up mediawiki for LDAP use
	LDAP_FULLDOM_UNDERSCORE=`echo $LDAPDOMAIN | sed s/dc\=//g | sed s/\,/_/g`
	sed -i "s/@LDAP_FULLDOM_UNDERSCORE@/${LDAP_FULLDOM_UNDERSCORE}/g" LocalSettings.php
	sed -i "s/@LDAP_FULLDOM_UNDERSCORE@/${LDAP_FULLDOM_UNDERSCORE}/g" LocalSettings.php
	sed -i "s/@LDAP_DN@/${LDAPDOMAIN}/g" LocalSettings.php
	sed -i "s/@LDAP_GROUP_OU@/${LDAPGRP}/g" LocalSettings.php
	# Password for DB
	echo Setting up mediawiki for PostgreSQL access
	sed -i "s/@DBNAME@/my_wiki/g" LocalSettings.php
	sed -i "s/@DBUSER@/wikiuser/g" LocalSettings.php
	sed -i "s/@DBPASS@/${PGSQL_PASS}/g" LocalSettings.php
	# Mail etc.
	echo Setting up mediawiki mail options
	sed -i "s/@ADMINMAIL@/admin@localhost/g" LocalSettings.php
	# The server itself etc.
	echo Setting up mediawiki site and servername
	sed -i "s/@SITENAME@/${SERVERNAME}/g" LocalSettings.php
	sed -i "s+@SERVERNAME@+http://${IPADDR}+g" LocalSettings.php
	sed -i "s+@PIWIK_URL@+/${IPADDR}/piwik+g" LocalSettings.php
	chown nginx:nginx LocalSettings.php
	echo Copying LocalSettings to medsettingsiawiki install
	sudo -u nginx cp LocalSettings.php /srv/mcweb/mediawiki/
	cd /srv/mcweb/mediawiki
	sudo -u nginx php maintenance/update.php
    fi
fi

# Self-service-password
cd /srv/mcweb
sudo -u nginx git clone https://github.com/ltb-project/self-service-password.git ssp
cd ssp/conf
sed -i "s/\$ldap_binddn = \"cn=manager,dc=example,dc=com\";/\$ldap_binddn = \"${LDAPADMIN}\";/g" config.inc.php
sed -i "s/\$ldap_bindpw = \"secret\";/\$ldap_bindpw = \"${LDAP_PASS}\";/g" config.inc.php
sed -i "s/\$ldap_base = \"dc=example,dc=com\";/\$ldap_base = \"${LDAPDOMAIN}\";/g" config.inc.php
sed -i "s/\$use_questions = true;/\$use_questions = false;/g" config.inc.php
sed -i "s/\$use_sms = true;/\$use_sms = false;/g" config.inc.php
sed -i "s+\$logo = \"images/ltb-logo.png\";+\$logo = \"/static/eneutrons_63x50.png\";+g" config.inc.php
sed -i "s+\$background_image = \"images/unsplash-space.jpeg\";+\$background_image = \"\";+g" config.inc.php

# Simple, static "admin" landing page
cd /srv/mcweb
sudo -u nginx mkdir landing
sed "s/@HOSTNAME@/${SERVERNAME}/g" McWeb/landingpage/landingpage.in.html > landing/index.html
chown nginx:nginx landing/index.html

cd /srv/mcweb
sudo -u nginx mkdir McWeb/mcsimrunner/sim/intro-ns
sudo -u nginx cp /usr/share/mcstas/2.4.1/examples/templateSANS.instr /srv/mcweb/McWeb/mcsimrunner/sim/intro-ns/SANSsimple.instr
sudo -u nginx cp mcvenv/bin/activate McWeb_finishup
echo cd McWeb/mcsimrunner/ >> McWeb_finishup
echo python manage.py migrate >> McWeb_finishup
echo python manage.py collect_instr >>  McWeb_finishup
echo python manage.py ldap_initdb $LDAP_PASS >>  McWeb_finishup
echo echo Please assist Django in creation of your djangoadmin user: >>  McWeb_finishup
echo python manage.py createsuperuser --username=djangoadmin --email=admin@localhost >>  McWeb_finishup >>  McWeb_finishup
echo echo -n Please enter your Django admin user pass again and press \[ENTER\]: >>  McWeb_finishup
echo read DJANGO_PASS >>  McWeb_finishup
echo python manage.py ldap_adduser $LDAP_PASS Django Admin djangoadmin admin@localhost \$DJANGO_PASS >>  McWeb_finishup
echo echo >>  McWeb_finishup
echo echo Essential setup done, here is a summary: >>  McWeb_finishup
echo echo >>  McWeb_finishup
echo echo LDAP setup: >>  McWeb_finishup
echo echo domainname: $LDAPDOMAIN >>  McWeb_finishup
echo echo admin string: $LDAPADMIN >>  McWeb_finishup
echo echo password: $LDAP_PASS >>  McWeb_finishup
echo echo >>  McWeb_finishup
echo echo MySQL setup: >>  McWeb_finishup
echo echo username: root >>  McWeb_finishup
echo echo password: $MYSQL_PASS >>  McWeb_finishup
echo echo >>  McWeb_finishup
echo echo PosgreSQL/mediawiki setup: >>  McWeb_finishup
echo echo username: wikiuser >>  McWeb_finishup
echo echo password: $PGSQL_PASS >>  McWeb_finishup
echo echo database: my_wiki >>  McWeb_finishup
echo echo >>  McWeb_finishup
echo echo Django setup: >>  McWeb_finishup
echo echo username: djangoadmin >>  McWeb_finishup
echo echo password: \$DJANGO_PASS >>  McWeb_finishup
echo echo email-adress: admin@localhost >>  McWeb_finishup
echo echo Django upload pass: $UPLOADPASS >>  McWeb_finishup
echo echo >>  McWeb_finishup 
echo crontab /srv/mcweb/McWeb/scripts/cronjobs.txt >> McWeb_finishup 

sudo -u nginx bash McWeb_finishup
/etc/init.d/uwsgi_mcweb start

cat /srv/mcweb/McWeb/scripts/nginx-default > /etc/nginx/default.d/mcweb.conf
service nginx restart


