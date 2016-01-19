#!/bin/bash

# Make sudo actually work
HOSTNAME=$(cat /etc/hostname)
echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
hostname $HOSTNAME

#Get the users SSH key from API, using JWT TOKEN
if [ -f /data/ssh_key ];
then
   echo "SSH key already exists."
else
   echo "SSH key does not exist. Fetching from API..."
   echo ${TOKEN:?"You need to set the TOKEN env var on you dashboard..."&& break}
   curl -H "Authorization: Bearer $TOKEN" 'https://api.resin.io/ewa/user__has__public_key?$select=id,title,public_key' | jq -r '.d[0].public_key' > /data/ssh_key
fi

cp -rf /data/ssh_key /root/.ssh/authorized_keys
chmod 640  /root/.ssh/authorized_keys

# Restarting the application re-fetches the current
# commit, therefore discards changes we make to /app
# directly.
# This workaround saves the changes to /data/.resin-watch
# and merges those changes to /app in each restart
mkdir -p /data/.resin-watch

# Only attempt to copy if the directory is not empty
if [ "$(ls -A /data/.resin-watch)" ]; then
  cp -rf /data/.resin-watch/* /usr/src/app/
fi

if [ "$INITSYSTEM" != "on" ]; then
  /usr/sbin/sshd -p 80 &
fi

coffee /usr/src/app/src/server.coffee | /usr/src/app/node_modules/bunyan/bin/bunyan -o short
