# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a self-hosted email server project built on Courier components (MTA, MSA, IMAP) running in Docker containers with systemd integration. The system supports virtual hosting, TLS/SSL encryption, and automated certificate management via Let's Encrypt.

## Key Architecture

### Core Components
- **MTA (Mail Transfer Agent)**: Handles incoming mail via courier-esmtpd
- **MSA (Mail Submission Agent)**: Handles outgoing mail submission
- **IMAP-SSL**: Provides secure IMAP access via courier-imapd-ssl
- **Courierd**: Local mail delivery daemon (runs in each container)
- **Template Renderer**: Rust-based tool for rendering configuration files

### Container Strategy
Each service runs in its own Docker container with shared volumes for:
- `/var/spool/courier` - Mail spool directories
- `/vmail/<domain>` - Virtual mail storage
- SSL certificates from Let's Encrypt
- Configuration rendered from context.json

### Configuration System
- **Context File**: `/etc/mailbag/context.json` (based on `examples/example-context.json`)
- **Template Rendering**: Uses custom Rust `render-template` tool with minijinja
- **Runtime Configuration**: Templates rendered at container startup

## Common Development Commands

### Building
```bash
# Build all containers and prerequisites
make

# Build just the template renderer
cd templater && cargo build

# Build service containers (done via GitHub Actions)
make service-images
```

### Testing
```bash
# Run goss validation tests
make run-goss

# Test STARTTLS functionality
./test-starttls.sh
```

### Deployment

#### Kubernetes Deployment (Recommended)
```bash
# Complete deployment workflow
./deploy-mailbag.sh

# Just check deployment status
./deploy-mailbag.sh status

# Individual steps:
# 1. Generate context configuration
./generate-context.sh

# 2. Generate and run host preparation
cd deployment/k8s && ./generate-host-scripts.sh && sudo ./prepare-host.sh

# 3. Deploy services to Kubernetes
cd deployment/k8s && sudo ./deploy-services.sh
```

#### Systemd Deployment (Alternative)
```bash
# Install systemd unit files
make install

# Start all services
make start

# Stop all services  
make stop

# Generate host-specific configuration
make host
```

### Template System
```bash
# Render a template manually
./render-template --context context.json --template template-file.template > output-file

# Generate unit files from templates
cd unit-files && make
```

## Important Files & Directories

### Configuration
- `context.json` - Main configuration (must be created from example)
- `examples/example-context.json` - Template for context configuration
- `unit-files/` - Systemd service definitions (templated)
- `entrypoints/` - Container startup scripts

### Build System
- `Dockerfile-*` - Container definitions for each service
- `build-*.sh` - Container build scripts  
- `Makefile` - Main build orchestration

### Templating
- `templater/` - Rust-based template renderer using minijinja
- `*.template` files - Template files for configuration

## Context Configuration

The system requires a `context.json` file (based on `examples/example-context.json`) containing:
- Domain names and DNS configuration
- SSL certificate paths (Let's Encrypt)
- Mail spool and storage paths
- Service-specific settings
- Docker network configuration

## Storage Architecture

### Path Standardization
All mailbag data is stored under `/home/` for consistency:
- Mail storage: `/home/vmail/<domain>/`
- Courier spool: `/home/mailbag/spool/courier-<service>/`
- Configuration: `/home/mailbag/config/{courier,authlib}/`
- Certificates: `/home/mailbag/letsencrypt/`

### Kubernetes Storage
- Uses hostPath PersistentVolumes with ReadWriteMany access
- Static volume binding with `storageClassName: ""` to avoid dynamic provisioning conflicts
- Supports IPC between courier components through shared filesystem

## Virtual Mail Setup

Users are managed via Courier's userdb system:
```bash
userdbpw -hmac-sha256 | userdb -f /etc/authlib/userdb/domain.com user@domain.com set hmac-sha256pw
userdb -f /etc/authlib/userdb/domain.com user@domain.com set uid=300 gid=300 home=/opt/vmail/domain.com/user
makeuserdb
```

## SSL/TLS Certificate Management

- Uses Let's Encrypt with certbot for certificate generation
- Certificates stored in `/etc/letsencrypt/live/<domain>-<generation>/`
- Renewal handled via systemd timers
- Containers mount certificate directories as volumes

## Kubernetes Support

Alternative deployment via Kubernetes is supported:
- Helm charts in `deployment/helm/mailbag/`
- Raw K8s manifests in `deployment/k8s/`
- Certificate management via cert-manager