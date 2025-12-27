# Compose Manager

`compose-manager.sh` is a Bash utility for managing multiple Docker Compose projects stored under a single root directory (for example `/docker` or `/home/bstetler/docker`).

It automatically discovers Compose projects, lets you manage them in bulk, shows what is running per project, and supports marking projects as inactive so they are skipped by default.

---

## Features

- Auto-discovers Docker Compose projects under a root directory
- Supports:
  - `compose.yml`
  - `compose.yaml`
  - `docker-compose.yml`
  - `docker-compose.yaml`
- Bulk management commands:
  - `list`
  - `status`
  - `check`
  - `pull`
  - `update`
  - `restart`
  - `down`
  - `prune`
- Displays running containers per project
- `.inactive` marker support
- Project filtering and dry-run support

---

## Install

```bash
chmod +x compose-manager.sh
sudo install -m 0755 compose-manager.sh /usr/local/sbin/compose-manager.sh
```

---

## Usage

Always specify the root directory that contains your Docker Compose projects.

Example root:

```
/home/bstetler/docker
```

---

## List projects and running containers

```bash
compose-manager.sh --root /home/bstetler/docker list
```

---

## Show Compose status per project

```bash
compose-manager.sh --root /home/bstetler/docker status
```

---

## Check for image updates (pull only, no restart)

```bash
compose-manager.sh --root /home/bstetler/docker check
```

---

## Pull images only

```bash
compose-manager.sh --root /home/bstetler/docker pull
```

---

## Update everything (pull + up -d)

```bash
compose-manager.sh --root /home/bstetler/docker update
```

---

## Update specific projects

```bash
compose-manager.sh --root /home/bstetler/docker update sonarr radarr overseerr
```

---

## Restart projects

```bash
compose-manager.sh --root /home/bstetler/docker restart
```

---

## Stop projects (docker compose down)

```bash
compose-manager.sh --root /home/bstetler/docker down
```

---

## Exclude projects

```bash
compose-manager.sh --root /home/bstetler/docker --exclude homeassistant --exclude ollama update
```

---

## Include only specific projects

```bash
compose-manager.sh --root /home/bstetler/docker --only sonarr --only radarr update
```

---

## Dry-run mode

```bash
compose-manager.sh --root /home/bstetler/docker --dry-run update
```

---

## Inactive Projects

```bash
compose-manager.sh --root /home/bstetler/docker inactive on stable-diffusion-webui
compose-manager.sh --root /home/bstetler/docker inactive off stable-diffusion-webui
compose-manager.sh --root /home/bstetler/docker inactive list
```

---

## Pruning

```bash
compose-manager.sh --root /home/bstetler/docker update --prune
compose-manager.sh --root /home/bstetler/docker prune
```

---

## Requirements

```bash
docker compose version
```
