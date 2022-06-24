OTHER_NS        = ns.ssr.com a.ns.spacey.org b.ns.spacey.org
AXFR_PORT       = 53
AXFR_CMD        = axfr-get
TCPCLIENT       = tcpclient
AXFR_DOMAINS    = spacey.org 


DOMAINS         = $(shell ./find_domains.sh)

.SILENT: 

data.cdb: $(DOMAINS)
        cat $(DOMAINS) > data
        /usr/bin/tinydns-data

axfr:
	for other_ns in $(OTHER_NS) ; do 
        for domain in $(AXFR_DOMAINS) ; do  \
          if ! [ -f domains/$$domain ] ; then \
            echo creating domains/$$domain ;\
            touch domains/$$domain ;\
          fi ;\
          tcpclient $(SSR) $(AXFR_PORT) $(AXFR_CMD) $$domain domains/tmp/$$domain domains/tmp/$$domain ; \
          export RV=$$? ; \
          if [ $$RV -eq 0 ] ; then \
              diff -q domains/$$domain domains/tmp/$$domain >/dev/null || \
                mv domains/tmp/$$domain domains/$$domain ; \
          else \
              echo $$domain failed with $$RV;  \
          fi ;\
        done
	done 


# data.cdb: data
#       /usr/local/bin/tinydns-data
