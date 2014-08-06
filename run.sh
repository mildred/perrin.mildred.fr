#!/bin/bash

name=${name}mildred

cat >/tmp/$$.mail.env <<EOF
LOCAL_DOMAINS=mildred.fr
EOF

gear install mildred/exim-dovecot-mail $name-mail --start \
  -p 4190:4190,25:25,993:993,143:143,465:465,587:587 \
  --env-file=/tmp/$$.mail.env

gear install mildred/roundcube $name-roundcube --start \
  -p 4433:4443

