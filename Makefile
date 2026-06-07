SHELL := /usr/bin/env bash

QS_CONFIG ?= noctalia-shell
QS_CMD ?= qs -c $(QS_CONFIG)
PLUGIN_ID ?= pi-assistant-panel
CACHE_DIR ?= $(HOME)/.cache/noctalia/plugins/$(PLUGIN_ID)
BACKEND_SOCKET ?= $(CACHE_DIR)/backend.sock
BACKEND_LOCK ?= $(BACKEND_SOCKET).lock
RESTART_LOG ?= $(CACHE_DIR)/noctalia-shell-restart.log
RUNTIME_DIR ?= /run/user/$(shell id -u)

.PHONY: help status shell-pids backend-pids stop-backend clean-backend stop-shell start-shell restart-shell logs tail-log ping-backend

help:
	@printf '%s\n' \
	  'Noctalia shell helper targets:' \
	  '  make status         Show shell/backend processes and backend socket state' \
	  '  make restart-shell  Stop backend, clear socket/lock, restart qs -c noctalia-shell' \
	  '  make start-shell    Start qs -c noctalia-shell in the current graphical session' \
	  '  make stop-shell     Stop qs -c noctalia-shell' \
	  '  make stop-backend   Stop this plugin backend daemon and Pi RPC child' \
	  '  make clean-backend  Remove stale backend socket and lock' \
	  '  make ping-backend   Ping the plugin backend socket' \
	  '  make logs           Show the restart log path and recent lines' \
	  '  make tail-log       Follow the restart log'

shell-pids:
	@pgrep -af '^$(QS_CMD)$$' || true

backend-pids:
	@ps -eo pid,args | awk '$$0 ~ /[p]i-rpc-bridge[.]py .*$(PLUGIN_ID)/ || $$0 ~ /[p]i --mode rpc/ {print}' || true

status:
	@echo '--- shell ---'
	@$(MAKE) --no-print-directory shell-pids
	@echo '--- backend ---'
	@$(MAKE) --no-print-directory backend-pids
	@echo '--- cache ---'
	@ls -l '$(CACHE_DIR)' 2>/dev/null || true

stop-backend:
	@set -euo pipefail; \
	if [[ -f '$(BACKEND_LOCK)' ]]; then \
	  pid=$$(cat '$(BACKEND_LOCK)' 2>/dev/null || true); \
	  if [[ -n "$$pid" ]] && kill -0 "$$pid" 2>/dev/null; then \
	    children=$$(pgrep -P "$$pid" || true); \
	    [[ -z "$$children" ]] || kill $$children 2>/dev/null || true; \
	    kill "$$pid" 2>/dev/null || true; \
	  fi; \
	fi; \
	fallback=$$(pgrep -f '[p]i-rpc-bridge[.]py .*$(PLUGIN_ID)|[p]i --mode rpc' || true); \
	[[ -z "$$fallback" ]] || kill $$fallback 2>/dev/null || true; \
	sleep 0.3; \
	fallback=$$(pgrep -f '[p]i-rpc-bridge[.]py .*$(PLUGIN_ID)|[p]i --mode rpc' || true); \
	[[ -z "$$fallback" ]] || kill -KILL $$fallback 2>/dev/null || true

clean-backend:
	@mkdir -p '$(CACHE_DIR)'
	@rm -f '$(BACKEND_SOCKET)' '$(BACKEND_LOCK)'

stop-shell:
	@set -euo pipefail; \
	pids=$$(pgrep -f '^$(QS_CMD)$$' || true); \
	if [[ -n "$$pids" ]]; then \
	  kill $$pids 2>/dev/null || true; \
	  for _ in $$(seq 1 30); do \
	    pgrep -f '^$(QS_CMD)$$' >/dev/null || break; \
	    sleep 0.2; \
	  done; \
	  remaining=$$(pgrep -f '^$(QS_CMD)$$' || true); \
	  [[ -z "$$remaining" ]] || kill -KILL $$remaining 2>/dev/null || true; \
	fi

start-shell:
	@mkdir -p '$(CACHE_DIR)'
	@set -euo pipefail; \
	export DBUS_SESSION_BUS_ADDRESS="$${DBUS_SESSION_BUS_ADDRESS:-unix:path=$(RUNTIME_DIR)/bus}"; \
	export XDG_RUNTIME_DIR="$${XDG_RUNTIME_DIR:-$(RUNTIME_DIR)}"; \
	export WAYLAND_DISPLAY="$${WAYLAND_DISPLAY:-wayland-1}"; \
	export DISPLAY="$${DISPLAY:-:0}"; \
	nohup $(QS_CMD) >'$(RESTART_LOG)' 2>&1 </dev/null & \
	echo "started $(QS_CMD) as pid $$!"; \
	sleep 2; \
	pgrep -af '^$(QS_CMD)$$' || true

restart-shell: stop-backend clean-backend stop-shell start-shell status

ping-backend:
	@python3 pi-rpc-bridge.py command --socket '$(BACKEND_SOCKET)' --json '{"command":"ping"}' --wait 1

logs:
	@echo '$(RESTART_LOG)'
	@tail -80 '$(RESTART_LOG)' 2>/dev/null || true

tail-log:
	@mkdir -p '$(CACHE_DIR)'
	@touch '$(RESTART_LOG)'
	@tail -f '$(RESTART_LOG)'
