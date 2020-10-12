#!/usr/bin/env bash

if [[ $UID != 0 ]]; then
    echo "требуется запуск c повышенными провами"
    exit 1
fi

newName=$1

[ "$newName" == "" ] && read -p "Ввести название домена: " fullname && newName=$fullname

[ "$(echo $newName | awk -F '.' '{print $2}')" != "loc" ] && newName=$newName.loc
echo новый домен: $newName

newNameConf=$newName.conf
webcatalog=/var/www

pathApache='/etc/apache2/sites-available'
pathApache_='/etc/apache2/sites-enabled/'

cat << EOF > $pathApache/$newNameConf
<VirtualHost *:80>
ServerName $newName 

ServerAdmin webmaster@localhost
DocumentRoot /var/www/$newName


ErrorLog ${APACHE_LOG_DIR}/error.log
CustomLog ${APACHE_LOG_DIR}/access.log combined

<Directory "/var/www/$newName">

RewriteEngine On
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule .* index.php [L]


    Order allow,deny
    Allow from all
  </Directory>


</VirtualHost>
EOF

ln -s $pathApache/$newNameConf $pathApache_/$newNameConf
mkdir $webcatalog/$newName

#chown maks. $webcatalog/$newName

echo "127.0.0.1 $newName" >> /etc/hosts

systemctl restart apache2.service



