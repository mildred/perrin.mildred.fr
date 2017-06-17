PLAYBOOKS=$(wildcard *.yml)

run: $(foreach p,$(PLAYBOOKS),$(p).ansible)

%.ansible: %
	cat $<
	ANSIBLE_NOCOWS=1 ansible-playbook $< -i localhost, -c local

.PHONY: run $(foreach ,,$(PLAYBOOKS))
