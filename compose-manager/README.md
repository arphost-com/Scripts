# Compose Manager

A simple Bash utility to manage many Docker Compose projects stored under a single root folder (e.g. `/docker` or `/home/bstetler/docker`). It auto-discovers Compose projects, can update them in bulk, and supports marking projects as inactive so they’re ignored by default.

## Features

- Auto-discover Compose projects under a root directory:
  - `compose.yml`, `compose.yaml`, `docker-compose.yml`, `docker-compose.yaml`
- Commands:
  - `list`, `status`, `check`, `pull`, `update`, `restart`, `down`, `prune`
- Shows running containers **per project**
- `.inactive` marker file support:
  - Projects with `.inactive` are skipped by default
  - Convenience commands: `inactive on/off/list`
- Filtering:
  - Run against selected projects: `update sonarr radarr`
  - Exclude projects: `--exclude homeassistant`
  - Include inactive projects: `--include-inactive`
  - Only inactive projects: `--only-inactive`
- Dry run mode: `--dry-run`

## Install

```bash
chmod +x compose-manager.sh
sudo install -m 0755 compose-manager.sh /usr/local/sbin/compose-manager.sh
