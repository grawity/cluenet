all: cacerts.pem

cacerts.pem: $(wildcard cacerts.d/*.pem)
	test $< && \
	cat $^ > $@
