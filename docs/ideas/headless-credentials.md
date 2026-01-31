# Headless Credentials Architecture

> Created: 2026-01-30
> Status: Design exploration
> Depends on: Phase 3 (headless automation)

## Problem Statement

Saetr's current credential model requires human interaction:

```
Human SSH → Unlock GPG → Unlock 1Password → Approve MFA → Work
```

For headless/autonomous operation, we need credentials available without a human present to unlock them.

### Current Credential Flow (Interactive)

```
┌─────────────────────────────────────────────────────────────────┐
│ Your Machine                                                    │
│                                                                 │
│  1Password ──biometric──► op CLI ──► ~/.config/secrets/         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ scp / mount
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Saetr VPS                                                       │
│                                                                 │
│  You ──SSH──► unlock GPG ──► gpg-agent caches passphrase        │
│                    │                                            │
│                    ▼                                            │
│  aws-vault ──► pass (GPG-encrypted) ──► TOTP + STS tokens       │
│                                                                 │
│  Containers mount:                                              │
│    ~/.gnupg (rw)           ← GPG keys + agent socket            │
│    ~/.password-store (rw)  ← Encrypted credentials              │
│    ~/.config/secrets (ro)  ← API tokens from 1Password          │
│    ~/.ssh (ro)             ← SSH keys                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Headless Challenge

| Step | Interactive | Headless |
|------|-------------|----------|
| GPG unlock | Human enters passphrase | ??? |
| 1Password | Human biometric/password | ??? |
| AWS MFA | Human enters TOTP | ??? |
| SSH passphrase | Human enters passphrase | ??? |

---

## Credential Inventory

| Credential | Current Source | Used For | Sensitivity |
|------------|----------------|----------|-------------|
| Anthropic API key | 1Password → env file | Claude Code | Medium |
| GitHub PAT | 1Password → env file | Push, PR, API | Medium |
| GitHub SSH key | ~/.ssh (passphrase?) | Git operations | Medium |
| AWS credentials | aws-vault + pass | Cloud resources | High |
| AWS MFA TOTP | pass + oathtool | STS token generation | High |
| NPM token | 1Password → env file | Package publishing | High |
| Linear API key | 1Password → env file | Ticket reading | Low |
| Other API keys | 1Password → env file | Various integrations | Low-Medium |

---

## Design Options

### Option 1: Long-Lived Unlocked Session

**Concept:** Keep credentials unlocked for extended periods. You unlock once, headless tasks use the cached session.

**Implementation:**
```bash
# ~/.gnupg/gpg-agent.conf
default-cache-ttl 604800      # 7 days
max-cache-ttl 2592000         # 30 days

# Systemd user service to keep agent alive
# ~/.config/systemd/user/gpg-agent-keepalive.service
```

**For 1Password:**
```bash
# Long-lived session (not officially supported, sessions expire after 30 min idle)
# Would need to re-auth periodically or use service accounts
```

**Pros:**
- Minimal architecture changes
- Works with current setup
- Simple mental model

**Cons:**
- Credentials exposed longer
- Sessions can expire unexpectedly
- Cold start still requires human
- 1Password sessions have hard limits

**Security rating:** ⚠️ Moderate risk

**Decision:** [ ] Use  [ ] Skip  [ ] Partial (GPG only)

**Notes:**
```




```

---

### Option 2: 1Password Service Accounts

**Concept:** Use [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/) designed for automation.

**How it works:**
```bash
# Service account token (stored securely on host)
export OP_SERVICE_ACCOUNT_TOKEN="ops_eyJ..."

# Fetch secrets without interactive auth
op read "op://Automation/GitHub PAT/credential"
op read "op://Automation/Anthropic API Key/credential"
```

**Setup:**
1. Create "Automation" vault in 1Password
2. Create service account with access only to that vault
3. Store service account token on Saetr host (encrypted at rest)
4. Containers request secrets via daemon proxy or direct op CLI

**Vault structure:**
```
Automation (vault)
├── GitHub PAT
├── Anthropic API Key
├── Linear API Key
├── NPM Token (if needed for headless)
└── AWS Access Key (if not using IAM roles)
```

**Pros:**
- Purpose-built for automation
- Scoped to specific vault
- Audit logging in 1Password
- No session expiry issues

**Cons:**
- Service account token needs protection
- Cost: ~$20/month per service account (Team plan)
- Separate from your personal vault

**Security rating:** ✅ Good

**Decision:** [ ] Use  [ ] Skip

**Estimated cost:** $__/month

**Notes:**
```




```

---

### Option 3: Credential Proxy Service

**Concept:** Daemon holds credentials, containers request via authenticated API.

**Architecture:**
```
┌─────────────────────────────────────────────────────────────────┐
│ Saetr Host                                                      │
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ saetr daemon (credential proxy)                            │ │
│  │                                                            │ │
│  │  Credential Store:          Audit Log:                     │ │
│  │  ┌──────────────────┐      ┌──────────────────────────┐   │ │
│  │  │ github: <token>  │      │ 2026-01-30 task-1 github │   │ │
│  │  │ anthropic: <key> │      │ 2026-01-30 task-2 aws    │   │ │
│  │  │ aws: <role/creds>│      │ ...                      │   │ │
│  │  └──────────────────┘      └──────────────────────────┘   │ │
│  │                                                            │ │
│  │  API: localhost:8080                                       │ │
│  │  ├── GET  /credentials/:name                               │ │
│  │  ├── POST /credentials/request (for JIT approval)          │ │
│  │  └── GET  /credentials/audit                               │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ▲                                  │
│                              │ localhost only                   │
│  ┌───────────────────────────┴──────────────────────────────┐   │
│  │                                                          │   │
│  │  Container 1              Container 2                    │   │
│  │  ┌──────────────┐        ┌──────────────┐               │   │
│  │  │              │        │              │               │   │
│  │  │ curl proxy/  │        │ curl proxy/  │               │   │
│  │  │ credentials/ │        │ credentials/ │               │   │
│  │  │ github       │        │ aws          │               │   │
│  │  │              │        │              │               │   │
│  │  └──────────────┘        └──────────────┘               │   │
│  │                                                          │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**API design:**
```bash
# Container requests credential
curl -X GET http://host.docker.internal:8080/credentials/github \
  -H "X-Task-ID: task-abc123" \
  -H "X-Container-ID: project-1"

# Response
{
  "credential": "ghp_...",
  "expires_at": "2026-01-30T12:00:00Z",  # optional
  "scope": "repo,read:org"
}

# Proxy checks:
# 1. Validate X-Task-ID exists and is active
# 2. Check task's permission tier allows 'github' credential
# 3. Log access: (timestamp, task_id, container_id, credential_name)
# 4. Return credential
```

**Per-tier access control:**
```yaml
# ~/.saetr/credentials.yaml
tiers:
  full:
    allowed: [github, anthropic, aws, npm, linear, ssh]

  scoped:
    allowed: [github, anthropic, linear]
    github:
      scope: "repo"  # not admin

  isolated:
    allowed: [anthropic]  # read-only operations only
```

**Credential sources:**
```yaml
# ~/.saetr/credentials.yaml
sources:
  github:
    type: 1password
    item: "op://Automation/GitHub PAT/credential"

  anthropic:
    type: env
    var: ANTHROPIC_API_KEY

  aws:
    type: iam_role
    role_arn: "arn:aws:iam::123456789:role/SaetrHeadless"

  npm:
    type: 1password
    item: "op://Automation/NPM Token/credential"
    require_approval: true  # JIT approval for sensitive creds
```

**Pros:**
- Credentials never stored in containers
- Centralized audit logging
- Per-task scoping
- Can integrate multiple backends (1Password, env, IAM roles)
- Foundation for just-in-time approval

**Cons:**
- New service to build and maintain
- Single point of failure
- Proxy itself must be secured
- More complexity

**Security rating:** ✅✅ Best

**Decision:** [ ] Use  [ ] Skip

**Notes:**
```




```

---

### Option 4: AWS IAM Roles + OIDC Federation

**Concept:** Eliminate AWS credentials entirely using IAM Roles with OIDC.

**How it works:**
```
Container ──► Requests OIDC token from Saetr daemon
          ──► Assumes IAM Role with token
          ──► Gets short-lived STS credentials (1 hour)
          ──► Uses AWS normally
```

**Architecture:**
```
┌──────────────────────────────────────────────────────────────┐
│ AWS Account                                                  │
│                                                              │
│  IAM Role: SaetrHeadlessRole                                 │
│  ├── Trust policy: Allow OIDC provider                       │
│  └── Permissions: Scoped to what headless tasks need         │
│                                                              │
│  OIDC Provider: saetr.yourdomain.com                         │
│  └── Thumbprint verified                                     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
            ▲
            │ AssumeRoleWithWebIdentity
            │
┌───────────┴──────────────────────────────────────────────────┐
│ Saetr Host                                                   │
│                                                              │
│  saetr daemon                                                │
│  ├── Issues OIDC tokens for tasks                            │
│  └── Tokens include task_id, tier, permissions               │
│                                                              │
│  Container                                                   │
│  └── Uses OIDC token to get STS credentials                  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**Pros:**
- No long-term AWS credentials anywhere
- Short-lived tokens (1 hour)
- AWS CloudTrail shows which task assumed role
- Industry standard (GitHub Actions, GitLab CI do this)

**Cons:**
- Complex setup (OIDC provider, IAM configuration)
- Only solves AWS, not other credentials
- Requires domain and TLS for OIDC issuer
- May be overkill for single-user setup

**Security rating:** ✅✅ Excellent for AWS

**Decision:** [ ] Use  [ ] Skip  [ ] Defer to later

**Notes:**
```




```

---

### Option 5: Just-In-Time Approval

**Concept:** Tasks run in low-privilege mode until they need credentials, then pause for human approval.

**Flow:**
```
┌─────────────────────────────────────────────────────────────────┐
│ Task Execution                                                  │
│                                                                 │
│  1. Task starts (isolated tier - no credentials)                │
│     ├── Reads Linear ticket ✓ (public API, low-priv token)      │
│     ├── Plans implementation ✓ (Claude, no creds needed)        │
│     └── Writes code ✓ (local filesystem)                        │
│                                                                 │
│  2. Task needs to push to GitHub                                │
│     └── Requests 'github' credential                            │
│         └── Task tier doesn't have github access                │
│             └── PAUSE: Approval required                        │
│                                                                 │
│  3. Notification sent                                           │
│     ├── Slack DM: "Task ENG-123 needs GitHub access"            │
│     ├── [Approve for 1 hour] [Approve once] [Deny]              │
│     └── Mobile push notification                                │
│                                                                 │
│  4. Human approves                                              │
│     └── Credential proxy grants github token for 1 hour         │
│                                                                 │
│  5. Task resumes                                                │
│     ├── Pushes branch ✓                                         │
│     ├── Creates PR ✓                                            │
│     └── Credential expires after 1 hour                         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Approval options:**
```yaml
approval_options:
  - type: once
    description: "Grant for this request only"

  - type: timed
    durations: [1h, 4h, 24h]
    description: "Grant for duration"

  - type: task
    description: "Grant for remainder of this task"

  - type: permanent
    description: "Add to auto-approve list"
    requires: explicit_confirmation
```

**Notification channels:**
```yaml
notifications:
  approval_required:
    - channel: slack_dm
      priority: high
    - channel: push
      priority: high
    - channel: email
      priority: low
      delay: 5m  # only if not approved via other channel
```

**Pros:**
- Human stays in loop for sensitive operations
- Minimal credential exposure
- Good for high-risk credentials (npm publish, prod AWS)
- Audit trail of approvals

**Cons:**
- Adds latency (waiting for human)
- Not truly autonomous
- Annoying if many approvals needed
- Requires notification infrastructure

**Security rating:** ✅✅✅ Excellent

**Decision:** [ ] Use for all  [ ] Use for high-risk only  [ ] Skip

**Credentials requiring JIT approval:**
- [ ] GitHub push
- [ ] AWS (any)
- [ ] AWS (prod only)
- [ ] NPM publish
- [ ] Other: ___

**Notes:**
```




```

---

### Option 6: Hybrid Approach (Recommended)

**Concept:** Different strategies for different credentials based on risk.

**Credential classification:**

| Credential | Risk | Strategy | Rationale |
|------------|------|----------|-----------|
| Anthropic API | Low | Always available | Needed constantly, limited blast radius |
| Linear API | Low | Always available | Read-only ticket access |
| GitHub (read) | Low | Always available | Public repos, limited scope |
| GitHub (push) | Medium | Proxy + audit | Want to know what's pushed |
| AWS (dev) | Medium | IAM Role or proxy | Dev account, limited impact |
| AWS (prod) | High | JIT approval | Production access, human should approve |
| NPM publish | High | JIT approval | Supply chain risk |
| SSH deploy keys | Medium | Proxy + audit | Server access |

**Recommended architecture:**

```
┌─────────────────────────────────────────────────────────────────┐
│ saetr daemon                                                    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Credential Proxy                                        │    │
│  │                                                         │    │
│  │  Always Available:        Proxy + Audit:                │    │
│  │  ├── anthropic            ├── github (push)             │    │
│  │  ├── linear               ├── aws (dev)                 │    │
│  │  └── github (read)        └── ssh                       │    │
│  │                                                         │    │
│  │  JIT Approval Required:                                 │    │
│  │  ├── aws (prod)                                         │    │
│  │  └── npm                                                │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Approval Queue                                          │    │
│  │                                                         │    │
│  │  Pending:                                               │    │
│  │  └── task-abc: aws-prod, requested 2m ago               │    │
│  │                                                         │    │
│  │  Approved:                                              │    │
│  │  └── task-xyz: npm, expires in 45m                      │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Credential Sources                                      │    │
│  │                                                         │    │
│  │  1Password Service Account ──► Low/medium risk creds    │    │
│  │  AWS IAM Role ──────────────► AWS dev access            │    │
│  │  Local encrypted file ──────► Fallback/overrides        │    │
│  │                                                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Configuration:**
```yaml
# ~/.saetr/credentials.yaml

sources:
  1password:
    type: service_account
    token_path: ~/.saetr/secrets/op-service-account-token
    vault: Automation

  aws_dev:
    type: iam_role
    role_arn: arn:aws:iam::123456789:role/SaetrDev

  aws_prod:
    type: iam_role
    role_arn: arn:aws:iam::123456789:role/SaetrProd

credentials:
  anthropic:
    source: 1password
    item: "Anthropic API Key"
    access: always

  linear:
    source: 1password
    item: "Linear API Key"
    access: always

  github_read:
    source: 1password
    item: "GitHub PAT (read)"
    access: always

  github_push:
    source: 1password
    item: "GitHub PAT (push)"
    access: proxy
    audit: true

  aws_dev:
    source: aws_dev
    access: proxy
    audit: true

  aws_prod:
    source: aws_prod
    access: jit
    approval_channels: [slack, push]
    default_duration: 1h

  npm:
    source: 1password
    item: "NPM Token"
    access: jit
    approval_channels: [slack, push]
    default_duration: 30m
```

**Pros:**
- Right-sized security for each credential
- Low friction for low-risk operations
- Human approval for high-risk operations
- Audit trail for medium-risk operations
- Flexible and extensible

**Cons:**
- Most complex to implement
- More configuration to maintain
- Need to classify each credential

**Security rating:** ✅✅✅ Excellent (balanced)

**Decision:** [ ] Use  [ ] Simplify (fewer tiers)

**Notes:**
```




```

---

## Implementation Phases

### Phase A: Foundation (Minimal Headless)

**Goal:** Enable headless operation with acceptable security trade-offs.

- [ ] Set up 1Password Service Account
- [ ] Create "Automation" vault with headless credentials
- [ ] Extend daemon with basic credential endpoint
- [ ] Containers fetch credentials from daemon
- [ ] Basic audit logging (append-only file)

**Credentials enabled:** anthropic, linear, github (all operations)

**Security trade-off:** All headless tasks share same credentials, limited audit granularity.

### Phase B: Proxy + Audit

**Goal:** Add per-task scoping and comprehensive audit trail.

- [ ] Implement credential proxy with tier checking
- [ ] Add task ID validation
- [ ] Structured audit logging (JSON, queryable)
- [ ] Separate read/push GitHub tokens
- [ ] AWS IAM role for dev account

**Credentials enabled:** All except high-risk (npm, aws-prod)

### Phase C: Just-In-Time Approval

**Goal:** Enable high-risk credentials with human approval.

- [ ] Implement approval queue in daemon
- [ ] Slack notification integration
- [ ] Mobile push notifications (optional)
- [ ] Approval CLI commands
- [ ] Time-bounded credential grants

**Credentials enabled:** All

### Phase D: Advanced (Optional)

**Goal:** Enterprise-grade credential management.

- [ ] OIDC provider for AWS federation
- [ ] HashiCorp Vault integration
- [ ] Credential rotation automation
- [ ] Anomaly detection (unusual access patterns)

---

## Cold Start Problem

**Scenario:** VPS reboots. How do credentials become available?

### Option A: Manual Unlock

After reboot, you SSH in and run:
```bash
saetr daemon unlock
# Prompts for GPG passphrase
# Authenticates to 1Password (if using CLI, not service account)
# Starts accepting credential requests
```

**Pros:** Most secure
**Cons:** Downtime until you unlock

### Option B: Encrypted Bootstrap

Service account token stored encrypted at rest, auto-decrypted on boot:
```bash
# Token encrypted with passphrase
~/.saetr/secrets/op-token.enc

# Systemd service decrypts on boot
# Passphrase stored in... where?
```

**Problem:** Where do you store the decryption passphrase?
- TPM (if available) - hardware-backed
- Separate cloud secret (AWS Secrets Manager) - chicken-and-egg
- Accept the risk and store plaintext - not recommended

**Pros:** Automatic recovery
**Cons:** Token accessible if disk compromised

### Option C: Degraded Mode

Daemon starts without credentials. Low-risk tasks can run (reading tickets, planning). High-risk tasks queue until human unlocks.

```bash
# After reboot, daemon is in degraded mode
saetr status
# Daemon: running (degraded - credentials locked)
# Queued: 3 tasks waiting for credentials

# You unlock when convenient
saetr daemon unlock
```

**Pros:** Tasks don't fail, just queue
**Cons:** Latency for credential-requiring tasks

### Recommendation

**Use 1Password Service Account** (token stored encrypted at rest) + **degraded mode for high-risk credentials**.

- Low/medium risk: Available immediately after boot
- High risk (npm, aws-prod): Require explicit unlock

**Decision:** [ ] Manual unlock  [ ] Encrypted bootstrap  [ ] Degraded mode  [ ] Hybrid

**Notes:**
```




```

---

## Security Considerations

### Threat Model

| Threat | Mitigation |
|--------|------------|
| VPS disk compromise | Encrypt secrets at rest; 1Password SA token in encrypted file |
| Container escape | Credentials never in container; proxy validates task ID |
| Rogue task | Permission tiers; JIT approval for high-risk |
| Stolen credential | Short-lived tokens where possible; audit trail for investigation |
| Network sniffing | Proxy on localhost only; TLS for external calls |
| Daemon compromise | Most severe; daemon is trusted computing base |

### Audit Requirements

What to log for each credential access:

```json
{
  "timestamp": "2026-01-30T12:34:56Z",
  "task_id": "task-abc123",
  "container_id": "project-1",
  "credential": "github_push",
  "tier": "scoped",
  "action": "granted",
  "expires_at": "2026-01-30T13:34:56Z",
  "client_ip": "172.17.0.2",
  "user_agent": "curl/7.88.0"
}
```

Audit log retention: [ ] 7 days  [ ] 30 days  [ ] 90 days  [ ] Indefinite

### Rotation Strategy

| Credential | Rotation Frequency | Method |
|------------|-------------------|--------|
| GitHub PAT | 90 days | Manual in 1Password |
| Anthropic API key | On compromise | Manual |
| AWS role credentials | Automatic (STS) | N/A |
| NPM token | 90 days | Manual in 1Password |
| 1Password SA token | 180 days | 1Password admin |

---

## Decision Summary

Fill out after reviewing options:

| Decision | Choice | Notes |
|----------|--------|-------|
| Primary credential store | [ ] 1Password SA  [ ] Vault  [ ] Files | |
| Credential proxy | [ ] Yes  [ ] No | |
| AWS strategy | [ ] IAM Role  [ ] Long-lived  [ ] JIT | |
| JIT approval for | [ ] npm  [ ] aws-prod  [ ] all push  [ ] none | |
| Cold start strategy | [ ] Manual  [ ] Auto  [ ] Degraded | |
| Audit log retention | [ ] 7d  [ ] 30d  [ ] 90d  [ ] Forever | |

---

## Open Questions

1. **1Password plan:** Do you have Team/Business (supports service accounts)?

2. **AWS account structure:** Single account or separate dev/prod? MFA required on both?

3. **Notification infrastructure:** Slack app exists? Push notification service preference?

4. **Risk tolerance:** Fully autonomous (accept more credential exposure) vs human-in-loop (more friction)?

5. **Multi-user future:** Will other team members use Saetr, or always single-user?

---

## References

- [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/)
- [AWS OIDC Federation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [HashiCorp Vault](https://www.vaultproject.io/)
- Current Saetr design: `docs/design.md`
- Phase 1 credentials section: `docs/design.md#credential-flow`
