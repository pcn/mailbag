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

## Courier Service Architecture (Kubernetes)

### Container Separation
The Kubernetes deployment uses a **single courierd container** for mail processing/delivery and **separate containers** for each listening service:

**courierd container**:
- Runs main courierd process as PID 1 with privileged mode
- Spawns worker processes with privilege separation:
  - `courierlocal` (root) - local mail delivery with setuid/setgid to target users
  - `courieresmtp` (daemon) - **outbound** SMTP delivery to remote servers
  - `courierdsn` (daemon) - delivery status notifications
  - `courieruucp` (uucp) - UUCP delivery
  - `courierfax` (root) - fax delivery
- These are **delivery agents**, not listening services
- Requires privileged mode for setuid/setgid operations during mail delivery

**Listening service containers**:
- `courier-msa` - Port 587 mail submission (authenticated clients)
- `courier-mta` - Port 25 incoming SMTP (external servers)
- `courier-mta-ssl` - Port 465 SSL SMTP
- `courier-imapd-ssl` - Port 993 IMAP access to mailboxes
- These run as daemon user (UID 1) except IMAP which runs as vmail (UID 300)

### Mail Flow
1. **Inbound**: MTA containers accept SMTP → queue to courier spool
2. **Submission**: MSA container accepts from clients → queue to courier spool  
3. **Processing**: courierd processes queue → local or remote delivery
4. **Local delivery**: courierlocal drops to target user → writes to `/vmail/user/Maildir/`
5. **Remote delivery**: courieresmtp sends to external servers
6. **Access**: IMAP reads maildirs as vmail user

### Communication
- Services communicate via **shared courier spool volume** (`/var/spool/courier`)
- No direct network communication between containers
- courierd must run privileged for mail delivery privilege separation
- MTA/MSA containers do NOT run courierd themselves (fixed architecture issue)

### User Permissions
- **daemon (UID 1)**: Courier services (MTA/MSA), courierd workers
- **vmail (UID 300)**: Mail storage access (IMAP, local delivery target)
- **root**: courierd main process, privilege-dropping delivery agents

## Security Considerations

### Certificate Handling (CRITICAL ISSUE)
**⚠️ SECURITY WARNING**: The current MSA entrypoint attempts to create `esmtpd.pem` in `/usr/lib/courier/share/` which is a shared directory. This is a security anti-pattern:

- Certificates and private keys should NOT be writable by daemon processes
- Shared directories should NOT have write permissions for service users
- Certificate material should be properly mounted with read-only permissions

**Action Required**: 
1. Stop using `/usr/lib/courier/share/esmtpd.pem` for certificate storage
2. Use proper certificate mounting with read-only permissions
3. Configure Courier to use the mounted certificate files directly
4. Implement proper certificate validation before deployment

**Current Status**: MSA service certificate handling is BLOCKED due to security concerns.

## Certificate Management with cert-manager (2025-06-24)

### Progress Made
- ✅ **cert-manager installed**: Deployed cert-manager v1.15.3 to Kubernetes cluster
- ✅ **Security decision**: Chose cert-manager over external certbot for proper K8s integration
- ✅ **CRDs deployed**: All cert-manager Custom Resource Definitions are available

### Next Steps (CONTINUE HERE NEXT SESSION)
1. **Wait for cert-manager pods**: Verify all cert-manager pods are Running
   ```bash
   kubectl get pods -n cert-manager
   ```

2. **Create Let's Encrypt ClusterIssuer**: Configure ACME issuer for farout.rton.me
   - Use HTTP-01 challenge for domain validation
   - Configure email for Let's Encrypt notifications

3. **Create Certificate resources**: Generate certificates for mail services
   - `mail.farout.rton.me` (MSA/MTA)
   - `smtp.farout.rton.me` (MTA-SSL)
   - `imap.farout.rton.me` (IMAP-SSL)

4. **Update deployments**: Modify courier services to use cert-manager secrets
   - Mount certificates as read-only volumes
   - Remove insecure certificate copying from entrypoints
   - Configure Courier to use mounted certificates directly

5. **Test certificate validation**: Verify certificates are valid and auto-renewing

### Why cert-manager over certbot
- ✅ Kubernetes-native certificate management
- ✅ Automatic renewal and secret updates
- ✅ Read-only certificate mounting (security best practice)
- ✅ No host-level dependencies
- ✅ Proper RBAC integration

## Current Deployment Status (2025-06-23)

### Working Components
- ✅ **courierd**: Running stably with privilege separation, processes mail queue
- ✅ **Storage**: All PVCs bound, shared courier spool functional
- ✅ **Configuration**: mailbag-context ConfigMap deployed
- ✅ **Architecture**: Fixed duplicate courierd issue, proper container separation

### Known Issues
- 🔄 **MTA/MSA services**: Need updated container images with fixed entrypoints (removed duplicate courierd startup)
- 🔄 **IMAP service**: CrashLoopBackOff, needs investigation
- 🔄 **Authentication**: Need to populate `/etc/authlib/userdb/` with test users
- 🔄 **Testing**: No end-to-end mail flow testing yet

### Next Steps
1. Wait for/deploy updated MTA/MSA/MTA-SSL container images (entrypoint fixes committed)
2. Apply updated service configurations with corrected user permissions
3. Create test user accounts in courier userdb
4. Test mail submission → delivery → IMAP access flow
5. Verify external mail reception works

### Architecture Notes for Next Session
- `courieresmtp` and `courierdsn` in courierd container are for **sending/delivery**, not listening
- MTA/MSA containers handle **listening** on SMTP ports, queue mail to shared spool
- Communication is **asynchronous** via filesystem, not direct container networking
- Only courierd needs privileged mode for privilege-dropping during delivery