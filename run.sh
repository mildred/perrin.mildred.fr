#!/bin/bash

echo 'DOCKER_OPTS="-r=false"' > /etc/default/docker

docker-unit(){
  local name="$1"
  shift
  local filename="/etc/systemd/system/$name.service"
  cat >"$filename" <<EOF
[Unit]
Description=Container $name
After=docker.service

[Service]
Restart=always
ExecStart=/usr/local/bin/docker-start-run $name $@
ExecStop=/usr/bin/docker stop -t 2 $name

[Install]
WantedBy=local.target
EOF
}

:> /usr/local/bin/docker-start-run
chmod +x /usr/local/bin/docker-start-run
cat >>/usr/local/bin/docker-start-run <<"EOF"
#!/bin/bash

name="$1"
shift

if ! /usr/bin/docker inspect --format="Reusing {{.ID}}" "$name-data" 2>/dev/null; then
  docker run --name "$name-data" --volumes-from "$name-data" --entrypoint /bin/true "$@"
fi

/usr/bin/docker rm "$name"
exec /usr/bin/docker run --rm --attach=stdout --attach=stderr --name="$name" --volumes-from="$name-data" "$@"

if docker inspect --format="Reusing {{.ID}}" "$name" 2>/dev/null; then
  exec /usr/bin/docker start -a "$name"
else
  exec /usr/bin/docker run --attach=stdout --attach=stderr --name="$name" --volumes-from="$name-data" "$@"
fi

EOF

docker run --rm -v /usr/local/bin:/target jpetazzo/nsenter

docker-ssh(){
  local user="$1"
  local name="$1"
  local shell="/bin/bash"
  shift
  while true; do
    case "$1" in
      -u*)       user="${1#-?}"   ;;
      -s*)       shell="${1#-?}"  ;;
      --user=*)  user="${1#-*=}"  ;;
      --shell=*) shell="${1#-*=}" ;;
      *)         break            ;;
    esac
    shift
  done
  [ "${shell//\//}" = "$shell" ] && shell="/bin/$shell"
  local ssh_key="$*"
  if uid="$(id -u "$user" 2>/dev/null)"; then
    if [ "0$uid" = 00  ]; then
      echo "Using existing user $user for ssh access"
    else
      echo "Existing user $user cannot be used for ssh access (uid $uid should be 0)" >&2
      return 1
    fi
  else
    echo "Creating user $user for ssh access"
    useradd -d /home/$user -N -m -o -u 0 $user
  fi
  mkdir -p /home/$user/.ssh
  chown -R $user /home/$user
  (
    fgrep -v "$ssh_key" /home/$user/.ssh/authorized_keys 2>/dev/null
    echo "command=\"nsenter --target \$(docker inspect --format {{.State.Pid}} $name) --mount --uts --ipc --net --pid $shell\" $ssh_key"
  ) | sort | uniq >/home/$user/.ssh/authorized_keys-
  mv /home/$user/.ssh/authorized_keys- /home/$user/.ssh/authorized_keys
}

systemctl-enable-start(){
  systemctl enable "$@"
  systemctl start "$@"
}


name=mildred
LOCAL_DOMAINS=mildred.fr
ssh_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDByLP6c0nvG8itxtyf9ucG6wQG5r6/mwJcPw7aFQb26930zRTOi+PfMjMFBWrhwkFDktlnTBGOvp+bygU4JuipU3pR5BL5o+Lrawd+Uu00kkhxlmkTzP1WYcdpbgBlXutLTuta5Gt4c3e8xUwdcvGHTizKZZZ+BENaOv7j2yfAaJnBJCKcdoI7WCBhuezRWfC2URfVMad/mPxECei/SzGcjhjh1hQiogXH9jwXsrrsU0nuMy8H2LWgqp2nDGFVvqInKC0ICWwDuhpNT21OB0KGdd7LxYdlve/CaMKYRhRMBLmu+grV8akGkmD0uGmF5fVNUOxcRW8PZnCEPiIFvgcv"

docker pull mildred/exim-dovecot-mail
docker pull mildred/roundcube
docker pull mildred/varnish
docker pull mildred/p2pweb

docker-unit $name-mail      "-p 4190:4190 -p 25:25 -p 993:993 -p 143:143 -p 465:465 -p 587:587 -e \"LOCAL_DOMAINS=$LOCAL_DOMAINS\" mildred/exim-dovecot-mail"
docker-unit $name-roundcube "-p 4443:443 --link \"$name-mail:mail\" mildred/roundcube"
docker-unit $name-p2pweb    "-p 8888:8888 -p 0.0.0.0:8888:8888/udp mildred/p2pweb"
docker-unit $name-varnish   "-p 80:80 --link \"$name-roundcube:webmail\" --link \"$name-p2pweb:p2pweb\" mildred/varnish"
docker-ssh  $name-mail      "$ssh_key"
docker-ssh  $name-roundcube "$ssh_key"
docker-ssh  $name-p2pweb    "$ssh_key"
docker-ssh  $name-varnish   "$ssh_key"

systemctl-enable-start $name-mail.service $name-roundcube.service $name-varnish.service $name-p2pweb.service

etc_varnish="$(docker inspect -f '{{(index .Volumes "/etc/varnish")}}' $name-varnish-data)"

cat >$etc_varnish/default.vcl <<"EOF"
backend webmail {
    .host = "%WEBMAIL_PORT_80_TCP_ADDR%";
    .port = "%WEBMAIL_PORT_80_TCP_PORT%";
}

backend p2pweb {
    .host = "%P2PWEB_PORT_8888_TCP_ADDR%";
    .port = "%P2PWEB_PORT_8888_TCP_PORT%";
}

sub vcl_recv {
    if (req.http.host ~ "webmail.mildred.fr") {
        set req.backend = webmail;
    } else {
        set req.backend = p2pweb;
        set req.url = regsub(req.url, "^/", "/obj/3c7c91945d52d2cb8c84dc82d8e4dd1dbc3d6ddd/");
    }
}

# 
# Below is a commented-out copy of the default VCL logic.  If you
# redefine any of these subroutines, the built-in logic will be
# appended to your code.
# sub vcl_recv {
#     if (req.restarts == 0) {
#         if (req.http.x-forwarded-for) {
#             set req.http.X-Forwarded-For =
#                 req.http.X-Forwarded-For + ", " + client.ip;
#         } else {
#             set req.http.X-Forwarded-For = client.ip;
#         }
#     }
#     if (req.request != "GET" &&
#       req.request != "HEAD" &&
#       req.request != "PUT" &&
#       req.request != "POST" &&
#       req.request != "TRACE" &&
#       req.request != "OPTIONS" &&
#       req.request != "DELETE") {
#         /* Non-RFC2616 or CONNECT which is weird. */
#         return (pipe);
#     }
#     if (req.request != "GET" && req.request != "HEAD") {
#         /* We only deal with GET and HEAD by default */
#         return (pass);
#     }
#     if (req.http.Authorization || req.http.Cookie) {
#         /* Not cacheable by default */
#         return (pass);
#     }
#     return (lookup);
# }
# 
# sub vcl_pipe {
#     # Note that only the first request to the backend will have
#     # X-Forwarded-For set.  If you use X-Forwarded-For and want to
#     # have it set for all requests, make sure to have:
#     # set bereq.http.connection = "close";
#     # here.  It is not set by default as it might break some broken web
#     # applications, like IIS with NTLM authentication.
#     return (pipe);
# }
# 
# sub vcl_pass {
#     return (pass);
# }
# 
# sub vcl_hash {
#     hash_data(req.url);
#     if (req.http.host) {
#         hash_data(req.http.host);
#     } else {
#         hash_data(server.ip);
#     }
#     return (hash);
# }
# 
# sub vcl_hit {
#     return (deliver);
# }
# 
# sub vcl_miss {
#     return (fetch);
# }
# 
# sub vcl_fetch {
#     if (beresp.ttl <= 0s ||
#         beresp.http.Set-Cookie ||
#         beresp.http.Vary == "*") {
#                 /*
#                  * Mark as "Hit-For-Pass" for the next 2 minutes
#                  */
#                 set beresp.ttl = 120 s;
#                 return (hit_for_pass);
#     }
#     return (deliver);
# }
# 
# sub vcl_deliver {
#     return (deliver);
# }
# 
# sub vcl_error {
#     set obj.http.Content-Type = "text/html; charset=utf-8";
#     set obj.http.Retry-After = "5";
#     synthetic {"
# <?xml version="1.0" encoding="utf-8"?>
# <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
#  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
# <html>
#   <head>
#     <title>"} + obj.status + " " + obj.response + {"</title>
#   </head>
#   <body>
#     <h1>Error "} + obj.status + " " + obj.response + {"</h1>
#     <p>"} + obj.response + {"</p>
#     <h3>Guru Meditation:</h3>
#     <p>XID: "} + req.xid + {"</p>
#     <hr>
#     <p>Varnish cache server</p>
#   </body>
# </html>
# "};
#     return (deliver);
# }
# 
# sub vcl_init {
#         return (ok);
# }
# 
# sub vcl_fini {
#         return (ok);
# }

EOF

systemctl restart $name-varnish.service
systemctl restart $name-p2pweb.service


