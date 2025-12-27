# Compose Manager

`compose-manager.sh` is a Bash utility for managing multiple Docker Compose projects stored under a single root directory (for example `/docker` or `/home/bstetler/docker`).

It automatically discovers Compose projects, lets you manage them in bulk, shows what is running per project, and supports marking projects as inactive so they are skipped by default.

## Features

- Auto-discovers Docker Compose projects under a root directory
- Supports:
  - compose.yml
  - compose.yaml
  - docker-compose.yml
  - docker-compose.yaml
- Bulk management commands:
  - list
  - status
  - check
  - pull
  - update
  - restart
  - down
  - prune
- Displays running containers per project
- `.inactive` marker support:
  - Inactive projects are skipped by default
  - Built-in commands to enable/disable inactive status
- Filtering options:
  - Target specific projects
  - Exclude projects
  - Include or operate only on inactive projects
- Dry-run mode for safety

## Install

```bash
chmod +x compose-manager.sh
sudo install -m 0755 compose-manager.sh /usr/local/sbin/compose-manager.sh

```markdown
## Usage

Always specify the root directory that contains your Docker Compose projects.

Example root used below:

/home/bstetler/docker



## List projects and running containers

Displays all discovered Compose projects and lists running containers per project.  
Projects marked inactive are skipped by default.

```bash
compose-manager.sh --root /home/bstetler/docker list

```markdown
## Show Compose status per project

Runs `docker compose ps` for each project.

```bash
compose-manager.sh --root /home/bstetler/docker status

```markdown
## Check for image updates (pull only, no restart)

Checks for updated images by running `docker compose pull`.  
Images may be downloaded, but containers are not restarted.

```bash
compose-manager.sh --root /home/bstetler/docker check

```markdown
## Pull images only

Pulls images for all selected projects without restarting containers.

```bash
compose-manager.sh --root /home/bstetler/docker pull

```markdown
## Update everything (pull + up -d)

Pulls images and applies updates using `docker compose up -d`.  
Inactive projects are skipped unless explicitly included.

```bash
compose-manager.sh --root /home/bstetler/docker update

```markdown
## Update specific projects

Only updates the specified project directories.

```bash
compose-manager.sh --root /home/bstetler/docker update sonarr radarr overseerr

```markdown
## Restart projects

Restarts containers for all selected projects.

```bash
compose-manager.sh --root /home/bstetler/docker restart

Restart a single project:

compose-manager.sh --root /home/bstetler/docker restart homeassistant

```markdown
## Stop projects (docker compose down)

Stops and removes containers for selected projects.

```bash
compose-manager.sh --root /home/bstetler/docker down

```markdown
## Exclude projects

Exclude one or more projects by directory name.

```bash
compose-manager.sh --root /home/bstetler/docker --exclude homeassistant --exclude ollama update

```markdown
## Include only specific projects

Limit actions to only the listed projects.

```bash
compose-manager.sh --root /home/bstetler/docker --only sonarr --only radarr update

```markdown
## Dry-run mode

Shows what commands would be executed without making any changes.

```bash
compose-manager.sh --root /home/bstetler/docker --dry-run update

```markdown
## Inactive Projects

Projects can be marked inactive using a `.inactive` marker file.  
Inactive projects are ignored by default.

### Mark a project inactive

Creates a `.inactive` file in the project directory.

```bash
compose-manager.sh --root /home/bstetler/docker inactive on stable-diffusion-webui

```markdown
### Mark a project active again

Removes the `.inactive` file.

```bash
compose-manager.sh --root /home/bstetler/docker inactive off stable-diffusion-webui

```markdown
### List inactive projects

```bash
compose-manager.sh --root /home/bstetler/docker inactive list

```markdown
### Include inactive projects in commands

```bash
compose-manager.sh --root /home/bstetler/docker --include-inactive list
compose-manager.sh --root /home/bstetler/docker --include-inactive update

```markdown
### Operate only on inactive projects

```bash
compose-manager.sh --root /home/bstetler/docker --only-inactive list

```markdown
## Pruning

Pruning removes unused Docker resources including images, networks, and volumes.

### Prune after another command

```bash
compose-manager.sh --root /home/bstetler/docker update --prune

```markdown
### Prune by itself

```bash
compose-manager.sh --root /home/bstetler/docker prune

```markdown
## Safety Notes

- `check` runs `docker compose pull` but does not restart containers
- `pull` only downloads images
- `update` pulls images and runs `up -d`; containers may restart
- Use `--dry-run` to preview actions before making changes

## Requirements

- Docker installed and working
- Docker Compose v2 plugin available as `docker compose`

```bash
docker compose version

---
