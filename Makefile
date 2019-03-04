NOMAD=nomad

PLAYBOOKS := \

EXCLUDED_PLAYBOOKS := \
	hashistack.yml \

PLAYBOOKS:=$(PLAYBOOKS) $(filter-out $(PLAYBOOKS) $(EXCLUDED_PLAYBOOKS),$(wildcard *.yml))

run-all: hashistack.yml.ansible run-nomad-jobs run-ansible-playbooks

run-ansible-playbooks: $(foreach p,$(PLAYBOOKS),$(p).ansible)

%.ansible: %
	cat $<
	ANSIBLE_NOCOWS=1 ansible-playbook $< -i localhost, -c local

run-nomad-jobs: *.nomad

%/NAMESPACE_ID:
	@base64 /dev/urandom | tr -d '/+' | dd bs=8 count=1 status=none >"$@"
	@printf "NS_ID\t%s %s\n" "$(dir $@)" "$$(cat "$@")"
	@#another way: </dev/urandom tr -dc 'a-zA-Z0-9' | head -c 8

generated/%.nomad/: NOMAD_SOURCE_DIR=$(patsubst generated/%,%,$@)
generated/%.nomad/: always
	@printf "MAKE\t%s\n" "$(NOMAD_SOURCE_DIR)"
	@test -e "$(NOMAD_SOURCE_DIR)NAMESPACE_ID" || $(MAKE) --no-print-directory $(NOMAD_SOURCE_DIR)NAMESPACE_ID
	@for d in $(NOMAD_SOURCE_DIR)*.nomad/; do \
		if [ -d "$$d" ]; then \
		 $(MAKE) --no-print-directory "generated/$$d"; \
		fi; \
	done
	@for f in $(NOMAD_SOURCE_DIR)*.nomad; do \
		if [ -f "$$f" ]; then \
		 $(MAKE) --no-print-directory "generated/$$f"; \
		fi; \
	done

generated/%.nomad: NOMAD_SOURCE_FILE=$(patsubst generated/%,%,$@)
generated/%.nomad: always
	@mkdir -p "$(dir $@)"
	@test -d "$@" && $(MAKE) --no-print-directory "$@/" || true
	@test -d "$(NOMAD_SOURCE_FILE)" || test -e "$(dir $(NOMAD_SOURCE_FILE))NAMESPACE_ID" || $(MAKE) --no-print-directory $(dir $(NOMAD_SOURCE_FILE))NAMESPACE_ID
	@test -d "$(NOMAD_SOURCE_FILE)" || printf "SED\t%s\n" "$(NOMAD_SOURCE_FILE)"
	@test -d "$(NOMAD_SOURCE_FILE)" || sed "s/{NS}/$$(cat "$(dir $(NOMAD_SOURCE_FILE))NAMESPACE_ID")/" >$@ <$(NOMAD_SOURCE_FILE)
	@test -d "$(NOMAD_SOURCE_FILE)" || for d in $(dir $(NOMAD_SOURCE_FILE))*.nomad; do \
		if [ -d "$$d" ]; then \
			name="$$(basename "$$d")"; \
			name="$$(echo $${name%%.nomad} | tr 'a-z-' 'A-Z_')"; \
			(set -x; sed "s/{NS_$$name}/$$(cat "$$d/NAMESPACE_ID")/" >$@- <$@); \
			mv "$@-" "$@"; \
		fi; \
	done

%.nomad/: generated/%.nomad always
	@test -e "$@"*.nomad/ && printf "NOMAD\t%s (subdirectories)\n" "$@" || true
	@for d in "$@"*.nomad/; do test -d "$$d" && $(MAKE) --no-print-directory "$$d"; done || true
	@printf "NOMAD\t%s\n" "$@"
	@for f in "$@"*.nomad; do test -f "$$f" && $(MAKE) --no-print-directory "$$f"; done || true

%.nomad: always
	@test -d "$@" && $(MAKE) --no-print-directory "$@/" || true
	@test -d "$@" || $(MAKE) --no-print-directory "generated/$@"
	@test -d "$@" || printf "NOMAD\t%s\n" "$@"
	@test -d "$@" || $(NOMAD) plan "generated/$@" || true
	@test -d "$@" || $(NOMAD) run "generated/$@"

always:
.PNONY: always


#A namespace is a collection of nomad jobs in the same directory. Sub-directories are sub-namespaces. When instanciated, a namespace is allocated an identifier (8 character unique ID). Before being inserted in nomad, the jobs are modified to include this namespace identifier:
#
#    the nomad job name is prefixed by "NAMESPACE-" (the namespace identifier)
#    the consul service definitions are prefixed by "NAMESPACE-" (the namespace identifier)
#    the services have an additional environment variable: CONSUL_NAMESPACE_ID
#
#sub-namespaces are also inserted in the system when their parent namespace is inserted. Each sub-namespace is given an identifier the same way. The parent namespace is instanciated with:
#
#    an environment variable CONSUL_NAMESPACE_ID_FOR_subnsname containing the sub namespace identifier
#
#We can imageine a complex system using namespace hierarchy like this:
#
#    main/ application namespace containing:
#        web-service.nomad (instanciated as "00000001-web-service")
#        helper.nomad (instanciated as "00000001-helper")
#        smtp/ server sub namespace:
#            exim.nomad (instanciated as "00000002-exim")
#            dovecot.nomad (instanciated as "0000002-dovecot")
#
#web-service knows how to contact exim because it can find it using the consul name "${CONSUL_NAMESPACE_ID_FOR_SMTP}-exim.service.consul"

debug:
	@echo PLAYBOOKS=$(PLAYBOOKS)

.PHONY: run $(foreach ,,$(PLAYBOOKS))
