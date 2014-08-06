#!/bin/bash

set -x
export DEBIAN_FRONTEND=noninteractive

cd
apt-get update
apt-get install -y golang stow

. "$(dirname "$0")/bootstrap-geard.sh"

systemctl enable geard.service
systemctl start geard.service
systemctl status geard.service

