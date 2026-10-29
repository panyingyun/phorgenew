#!/bin/bash

sleep 30

if id "$PHORGE_GIT_USER" >/dev/null 2>&1; then
  echo "user $PHORGE_GIT_USER already exists"
else
  addgroup "$PHORGE_GIT_USER"
  adduser "$PHORGE_GIT_USER" -G "$PHORGE_GIT_USER" -D -h /var/repo
fi

# Alpine adduser leaves the shadow password as "!", and OpenSSH 10 refuses
# pubkey logins for locked accounts. Set a random password (SSH passwords stay disabled).
if grep -q "^${PHORGE_GIT_USER}:!" /etc/shadow; then
  printf '%s:%s\n' "$PHORGE_GIT_USER" "$(head -c 24 /dev/urandom | base64 | tr -d '\n')" | chpasswd
fi

# PHP-FPM runs as www-data and sudo's to phd.user (git) for Diffusion commands.
# The rule must be www-data -> git, not git -> daemon.
sed -i "/^${PHORGE_GIT_USER} ALL=(daemon) SETENV: NOPASSWD:/d" /etc/sudoers
if ! grep -q "^www-data ALL=(${PHORGE_GIT_USER}) SETENV: NOPASSWD:" /etc/sudoers; then
  echo "www-data ALL=(${PHORGE_GIT_USER}) SETENV: NOPASSWD: /bin/ls, /usr/bin/git, /usr/bin/git-upload-pack, /usr/bin/git-receive-pack, /usr/bin/ssh, /usr/libexec/git-core/git-http-backend, /usr/lib/git-core/git-http-backend" >> /etc/sudoers
fi
chown -R "$PHORGE_GIT_USER" /var/repo
/var/www/phorge/phorge/bin/config set phd.user "$PHORGE_GIT_USER"
/var/www/phorge/phorge/bin/config set diffusion.ssh-user "$PHORGE_GIT_USER"

mkdir /run/sshd

mkdir /usr/libexec
cp /var/www/phorge/phorge/resources/sshd/phorge-ssh-hook.sh /usr/libexec/phorge-ssh-hook.sh
sed -i "s/vcs-user/$PHORGE_GIT_USER/g" /usr/libexec/phorge-ssh-hook.sh
sed -i "s/\/path\/to\/phorge/\/var\/www\/phorge\/phorge/g" /usr/libexec/phorge-ssh-hook.sh
chmod 755 /usr/libexec/phorge-ssh-hook.sh

cp /var/www/phorge/phorge/resources/sshd/sshd_config.phorge.example /etc/ssh/sshd_config.phorge
sed -i "s/vcs-user/$PHORGE_GIT_USER/g" /etc/ssh/sshd_config.phorge
sed -i "s/2222/$SSH_PORT/g" /etc/ssh/sshd_config.phorge
sed -i "s/PrintLastLog/#PrintLastLog/g" /etc/ssh/sshd_config.phorge

bash /regenerate-ssh-keys.sh
#Timezone configuration
/var/www/phorge/phorge/bin/config set phabricator.timezone $PHORGE_TIMEZONE
#SSH Configuration
/var/www/phorge/phorge/bin/config set diffusion.ssh-port $SSH_PORT
/var/www/phorge/phorge/bin/config set files.enable-imagemagick true
#DB configuration
/var/www/phorge/phorge/bin/config set mysql.host $PHORGE_MYSQL_HOST
/var/www/phorge/phorge/bin/config set mysql.port $PHORGE_MYSQL_PORT
/var/www/phorge/phorge/bin/config set mysql.user $PHORGE_MYSQL_USER
/var/www/phorge/phorge/bin/config set mysql.pass $PHORGE_MYSQL_PASS
/var/www/phorge/phorge/bin/config set diffusion.allow-http-auth true
/var/www/phorge/phorge/bin/config set diffusion.global-default-branch-git main
#Enable Git LFS (requires the git-lfs package, installed in the Dockerfile)
/var/www/phorge/phorge/bin/config set diffusion.allow-git-lfs true

if [ "$PROTOCOL" == "https" ]
then
    echo '<?php

$_SERVER['"'"'HTTPS'"'"'] = true;' > /var/www/phorge/phorge/support/preamble.php
fi

#Large file storage configuration
if [ "$PHORGE_STORAGE_ENGINE" == "local" ]
then
    mkdir -p /storage
    chown www-data:www-data /storage
    /var/www/phorge/phorge/bin/config set storage.local-disk.path /storage
fi

# S3 / MinIO / RustFS configuration — only when storage engine explicitly set to 's3'
if [ "$PHORGE_STORAGE_ENGINE" == "s3" ] && [ ! -z "$PHORGE_STORAGE_S3_SERVER" ] && [ ! -z "$PHORGE_STORAGE_S3_SERVER_SECRET_KEY" ] && [ ! -z "$PHORGE_STORAGE_S3_SERVER_ACCESS_KEY" ] && [ ! -z "$PHORGE_STORAGE_S3_PORT" ] && [ ! -z "$PHORGE_STORAGE_S3_REGION" ]
then
  /var/www/phorge/phorge/bin/config set storage.s3.bucket $PHORGE_STORAGE_S3_SERVER
  /var/www/phorge/phorge/bin/config set amazon-s3.secret-key $PHORGE_STORAGE_S3_SERVER_SECRET_KEY
  /var/www/phorge/phorge/bin/config set amazon-s3.access-key $PHORGE_STORAGE_S3_SERVER_ACCESS_KEY
  # Use plain HTTP for the local S3 endpoint (RustFS/MinIO on :9000). The
  # arcanist AWS client is patched (scripts/patch-aws-http.sh) to accept an
  # explicit scheme in the endpoint.
  /var/www/phorge/phorge/bin/config set amazon-s3.endpoint "http://$PHORGE_STORAGE_S3_SERVER:$PHORGE_STORAGE_S3_PORT"
  /var/www/phorge/phorge/bin/config set amazon-s3.region $PHORGE_STORAGE_S3_REGION
  # Force all files to the S3 engine instead of the MySQL blob engine
  # (Phorge picks the lowest-priority writable engine first; blob is priority 1).
  /var/www/phorge/phorge/bin/config set storage.mysql-engine.max-size 0
  # Create the S3 bucket if it does not exist (RustFS/MinIO do not create it
  # automatically; a 404 on PUT would otherwise be silently swallowed).
  php -r '
    require "/var/www/phorge/phorge/scripts/init/init-setup.php";
    $bucket = PhabricatorEnv::getEnvConfig("storage.s3.bucket");
    $s3 = id(new PhutilAWSS3Future())
      ->setAccessKey(PhabricatorEnv::getEnvConfig("amazon-s3.access-key"))
      ->setSecretKey(new PhutilOpaqueEnvelope(PhabricatorEnv::getEnvConfig("amazon-s3.secret-key")))
      ->setRegion(PhabricatorEnv::getEnvConfig("amazon-s3.region"))
      ->setEndpoint(PhabricatorEnv::getEnvConfig("amazon-s3.endpoint"))
      ->setBucket($bucket)
      ->setHTTPMethod("PUT")
      ->setPath($bucket);
    try {
      $s3->resolve();
      echo "S3 bucket \"".$bucket."\" ready\n";
    } catch (Exception $ex) {
      fwrite(STDERR, "WARNING: S3 bucket create failed: ".$ex->getMessage()."\n");
    }
  '
fi

# Configure SMTP mailer postfix
postfix set-permissions

if [ "$PHORGE_MAILER" == "postfix" ]
then
    sed -i -E "s|^[[:space:]]*#myhostname[[:space:]]*=[[:space:]]*host\.domain\.tld[[:space:]]*$|myhostname = ${PHORGE_BASE_URI}|" /etc/postfix/main.cf
    sed -i -E '/^\[program:postfix\]/,/^\[/{ s/^autostart=.*/autostart=true/; s/^autorestart=.*/autorestart=true/ }' /etc/supervisord.conf

    echo "[
      {
        \"key\": \"sendmail\",
        \"type\": \"sendmail\"
      }
    ]" > mailers.json

    /var/www/phorge/phorge/bin/config set cluster.mailers --stdin < mailers.json
    rm mailers.json
fi

if [ "$PHORGE_MAILER" == "smtp" ]
then
  if [ ! -z "$PHORGE_SMTP_SERVER" ] && [ ! -z "$PHORGE_SMTP_PORT" ] && [ ! -z "$PHORGE_SMTP_USER" ] && [ ! -z "$PHORGE_SMTP_PASSWORD" ] &&  [ ! -z "$PHORGE_SMTP_PROTOCOL" ]
  then
      echo "[
    {
      \"key\": \"smtp-mailer\",
      \"type\": \"smtp\",
      \"options\": {
        \"host\": \"$PHORGE_SMTP_SERVER\",
        \"port\": $PHORGE_SMTP_PORT,
        \"user\": \"$PHORGE_SMTP_USER\",
        \"password\": \"$PHORGE_SMTP_PASSWORD\",
        \"protocol\": \"$PHORGE_SMTP_PROTOCOL\"
      }
    }
  ]" > mailers.json
      /var/www/phorge/phorge/bin/config set cluster.mailers --stdin < mailers.json
      rm mailers.json
  fi
fi

# Update base uri
/var/www/phorge/phorge/bin/config set phabricator.base-uri "$PROTOCOL://$PHORGE_BASE_URI/"
sed -i "s/  server_name phorge.local;/  server_name $PHORGE_BASE_URI;/g" /etc/nginx/sites-available/phorge.conf
#sed "s/    return 301 \$scheme:\/\/phorge.local$request_uri;"
#general parameters configuration
/var/www/phorge/phorge/bin/config set pygments.enabled true
#setup db in not exists
/var/www/phorge/phorge/bin/storage upgrade --force
# nginx runs as www-data; the package temp dir is owned by nginx and blocks LFS uploads
mkdir -p /var/lib/nginx/tmp/client_body
chown -R www-data:www-data /var/lib/nginx
#start supervisord
/usr/bin/supervisord -n -c /etc/supervisord.conf
