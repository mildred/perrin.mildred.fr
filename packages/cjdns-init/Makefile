all:
	ln -sfT /etc/cjdroute.conf cjdroute.conf.link

install:
	mkdir -p $(DESTDIR)/etc/backup.d/cjdns-init/
	ln -sfT /etc/cjdroute.conf $(DESTDIR)/etc/backup.d/cjdns-init/cjdroute.conf.link
	install -D -m644 cjdroute.service $(DESTDIR)/usr/lib/systemd/system/cjdroute.service

