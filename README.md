# Vulnotes CLI

Command-line tool for managing on-prem Vulnotes deployments (requires a license).

## Requirements

- Docker & Docker Compose
- curl, jq, openssl

## Installation

**Option 1: Quick install**
```bash
curl -fsSL https://raw.githubusercontent.com/vulnotes/vulnotes-cli/master/install.sh | bash
```

**Option 2: Manual install**
```bash
git clone https://github.com/vulnotes/vulnotes-cli.git
cd vulnotes-cli
chmod +x vulnotes
```

## Usage

### Initialize a new deployment
```bash
./vulnotes init --token <provisioning-token>
```
*Provisioning token can be found on https://manager.vulnotes.com when you have a valid on-premise license. Tokens expire after 30 minutes.*

### Manage containers
```bash
./vulnotes start      # Start Vulnotes
./vulnotes stop       # Stop Vulnotes
./vulnotes restart    # Restart Vulnotes
./vulnotes update     # Pull latest images and restart
```

### View logs
```bash
./vulnotes logs              # All services
./vulnotes logs backend      # Specific service
./vulnotes logs -f           # Follow mode
```

### Backup & Restore
```bash
./vulnotes backup                              # Create backup
./vulnotes restore <backup-file>               # Full restore
./vulnotes restore <backup-file> --data-only   # Restore data only (for migrations)
```

### Reset
```bash
./vulnotes reset      # Wipe all data and return to a clean install
```
Deletes all data in the database (reports, findings, users, companies, templates), uploaded files, logs and the license cache, then restarts the stack into first-time setup.


## Configuration

After `init`, the following files are generated:

| File | Description |
|------|-------------|
| `.env` | Environment variables (JWT secret, domain) |
| `docker-compose.yml` | Docker services configuration |
| `nginx.conf` | Nginx reverse proxy configuration |
| `license.json` | License file |

## SSL/HTTPS

For production deployments, configure SSL using a reverse proxy like Traefik or Nginx with certificates from Let's Encrypt or another provider.

## Help

```bash
./vulnotes help
```
