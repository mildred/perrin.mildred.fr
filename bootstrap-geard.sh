#!/bin/sh
#See: https://aur.archlinux.org/packages/ge/geard-git/PKGBUILD
set -e

: ${PREFIX:=/usr/local}

mkdir -p $PREFIX/src/geard.go
cd $PREFIX/src/geard.go
export GOPATH="$PWD"

mkdir -p src/github.com/openshift
git clone https://github.com/openshift/geard.git src/github.com/openshift/geard || true

src/github.com/openshift/geard/contrib/build -n -l

sed "s:/usr/bin:$PREFIX/bin:g" src/github.com/openshift/geard/contrib/geard.service >geard.service

set -x

install -d $PREFIX/stow/geard/lib/systemd/system/ $PREFIX/stow/geard/bin/
for binfile in bin/*; do
  install -Dm755 $binfile $PREFIX/stow/geard/bin/${binfile##*/}
done
install -Dm644 geard.service $PREFIX/stow/geard/lib/systemd/system/


set +x

find $PREFIX/stow/geard

cd $PREFIX/stow
stow -R geard

echo "systemctl enable geard.service"
echo "systemctl start geard.service"
echo "systemctl status geard.service"
