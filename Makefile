
export ANSIBLE_NOCOWS=1

%:
	ansible-playbook -i hosts $@.yml