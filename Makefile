.PHONY: install uninstall deploy test logs status

install:
	bash scripts/install.sh

uninstall:
	bash scripts/uninstall.sh

deploy:
	bash scripts/deploy.sh

test:
	.venv/bin/pytest tests/ -v

logs:
	journalctl -u pve-net-broker -f

status:
	systemctl status pve-net-broker --no-pager
	@echo ""
	@curl -s http://127.0.0.1:7100/health | python3 -m json.tool

restart:
	systemctl restart pve-net-broker
