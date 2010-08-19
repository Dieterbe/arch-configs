DESTDIR?=/usr/local

install:
	install -d $(DESTDIR)/bin
	install -d $(DESTDIR)/share/arch-configs/docs
	install -m755 arch-configs.sh   $(DESTDIR)/bin/arch-configs
	install -m644 README $(DESTDIR)/share/arch-configs/docs

uninstall:
	rm -rf $(DESTDIR)/bin/arch-configs
	rm -rf $(DESTDIR)/share/arch-configs
