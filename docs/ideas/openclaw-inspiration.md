# OpenClaw-Inspired Features for Saetr

> Analysis date: 2026-01-30
> Source: https://github.com/openclaw/openclaw (formerly moltybot, clawdbot)

## Context

OpenClaw is a self-hosted personal AI assistant platform focused on multi-channel messaging integration. While solving a different problem (personal assistant vs autonomous development), several architectural decisions are worth considering for Saetr.

**Saetr's end goal:** Ping a ticket number → agent reads ticket, plans, implements, tests, submits PR, iterates on review feedback → PR ready for final human review and merge.

**What OpenClaw validates:** The interface/orchestration layer matters for adoption. Saetr has strong execution foundations; these ideas strengthen the orchestration layer.

---

## Feature Analysis

### 1. Daemon-Based Control Plane

**What OpenClaw does:**
- Persistent WebSocket server (`ws://127.0.0.1:18789`)
- Coordinates channels, agents, and tools
- Single process manages all state and routing

**Current Saetr state:**
- Stateless shell scripts
- No persistent orchestration
- Each command invocation is independent

**Proposed for Saetr:**
```
saetr daemon start
  ├── HTTP/WebSocket API on localhost:18789
  ├── Container lifecycle management
  ├── Task queue with persistence
  ├── Event emitter (task started, PR created, etc.)
  └── Health monitoring
```

**Benefits:**
- Foundation for all external integrations
- Real-time status without polling
- Crash recovery with persistent queue
- Single place to add new triggers

**Decision:** [ ] Implement  [ ] Skip  [ ] Defer

**If implementing, phase:** ___

**Notes:**
```




```

---

### 2. Multi-Channel Task Triggers

**What OpenClaw does:**
- Accepts input from WhatsApp, Telegram, Slack, Discord, Signal, iMessage, Teams, Matrix
- Unified inbox—same agent, many entry points

**Current Saetr state:**
- SSH + CLI only
- No external trigger support

**Proposed for Saetr:**

| Channel | Trigger Example | Complexity |
|---------|-----------------|------------|
| CLI | `saetr task create ENG-123` | Low |
| HTTP API | `curl -X POST /tasks -d '{"ticket":"ENG-123"}'` | Low |
| Slack | `/saetr implement ENG-123` | Medium |
| Linear webhook | Ticket assigned to "Saetr" → auto-start | Medium |
| GitHub | Issue comment `@saetr implement this` | Medium |
| Email | Forward ticket to saetr@yourdomain.com | High |

**Recommended priority:**
1. HTTP API (everything else is just a wrapper)
2. CLI (thin client calling HTTP API)
3. Slack (highest daily use)
4. Linear webhook (automation)
5. GitHub comments (nice to have)

**Decision:** [ ] Implement  [ ] Skip  [ ] Defer

**Channels to support:** ___

**Notes:**
```




```

---

### 3. Permission Tiers

**What OpenClaw does:**
- Main session: full tool access
- Non-main sessions: per-session Docker sandboxes
- `/elevated on|off` toggle for bash access
- macOS TCC integration for system permissions

**Current Saetr state:**
- All containers share same credentials
- No per-task permission scoping
- Acceptable for single-user, not for team/external triggers

**Proposed for Saetr:**

| Tier | Use Case | Credentials | Repos | Container |
|------|----------|-------------|-------|-----------|
| `full` | Your own tasks | All (aws, github, npm) | All | Persistent |
| `scoped` | Team member tasks | Limited (github only) | Allowlist | Persistent |
| `isolated` | External/bot tasks | None | Fresh clone | Ephemeral |

**Configuration example:**
```yaml
# ~/.saetr/permissions.yaml
tiers:
  full:
    credentials: [aws, github, npm, anthropic]
    repos: "*"
    container_type: persistent

  scoped:
    credentials: [github]
    repos:
      - "campusiq/api"
      - "campusiq/web"
      - "campusiq/mobile"
    container_type: persistent

  isolated:
    credentials: []
    repos: []
    container_type: ephemeral
    max_duration: 2h

# Default tier for different sources
source_defaults:
  cli: full
  slack_dm: full
  slack_channel: scoped
  webhook: isolated
  unknown: isolated
```

**Decision:** [ ] Implement  [ ] Skip  [ ] Defer

**Notes:**
```




```

---

### 4. Pairing/Approval Workflows

**What OpenClaw does:**
- Unknown senders receive pairing codes instead of denial
- Only approved contacts interact without explicit allowlisting
- Graceful handling of untrusted input

**Current Saetr state:**
- No concept of task approval
- Would need to either auto-run or reject external triggers

**Proposed for Saetr:**

```
# Flow for unapproved source
External trigger (Slack from unknown user)
    │
    ▼
Task created with status: pending_approval
    │
    ▼
Notification sent (Slack DM, push, email)
    │
    ├── Approve: `saetr approve <task-id> [--tier scoped]`
    │       │
    │       ▼
    │   Task runs
    │
    └── Deny: `saetr deny <task-id>`
            │
            ▼
        Task deleted, requester notified
```

**Auto-approval rules:**
```yaml
# ~/.saetr/approval.yaml
auto_approve:
  - source: cli
    tier: full

  - source: slack
    user: "@josh.park"
    tier: full

  - source: linear_webhook
    project: "ENG"
    assignee: "josh.park"
    tier: scoped

require_approval:
  - source: slack
    channel: "#dev"

  - source: github
    repo: "*"
```

**Decision:** [ ] Implement  [ ] Skip  [ ] Defer

**Notes:**
```




```

---

### 5. Inter-Agent Communication

**What OpenClaw does:**
- `sessions_list` - enumerate active sessions
- `sessions_history` - read another session's context
- `sessions_send` - message between sessions

**Current Saetr state:**
- Containers are isolated
- No inter-container communication
- No handoff workflow

**Proposed for Saetr:**

**Use case: Dev → Review → Iterate cycle**
```yaml
# Task definition with stages
task:
  ticket: ENG-123
  stages:
    - name: implement
      agent: dev
      container: project-1
      until: pr_created

    - name: review
      agent: review-bot
      container: project-1-review  # or same container
      until: approved | changes_requested

    - name: iterate
      agent: dev
      container: project-1
      when: changes_requested
      until: pr_updated
      goto: review
```

**Simpler alternative: Event log**
```
# Shared event stream all agents can read/write
~/.saetr/events/ENG-123.jsonl

{"ts": "...", "agent": "dev", "event": "pr_created", "pr": 142}
{"ts": "...", "agent": "review", "event": "changes_requested", "comments": [...]}
{"ts": "...", "agent": "dev", "event": "pr_updated", "commits": ["abc123"]}
```

Agents poll or watch the event log for their triggers.

**Decision:** [ ] Implement  [ ] Skip  [ ] Defer

**Approach preference:** [ ] Staged workflows  [ ] Event log  [ ] Both

**Notes:**
```




```

---

### 6. Skills/Templates Registry

**What OpenClaw does:**
- ClawHub: community registry for skills
- Bundled, managed, and workspace-level skills
- Install gating and automatic discovery

**Current Saetr state:**
- No project templates
- Manual setup for each new project

**Proposed for Saetr:**

```
saetr new my-api --template fastapi-postgres
saetr new my-app --template nextjs-prisma
saetr new my-cli --template python-typer
```

**Template structure:**
```
~/.saetr/templates/
├── fastapi-postgres/
│   ├── template.yaml         # metadata, variables
│   ├── scaffold/             # files to copy
│   │   ├── src/
│   │   ├── tests/
│   │   ├── Dockerfile
│   │   ├── pyproject.toml
│   │   └── CLAUDE.md         # agent instructions
│   └── hooks/
│       └── post-create.sh    # run after scaffold
└── nextjs-prisma/
    └── ...
```

**Template sources:**
```yaml
# ~/.saetr/config.yaml
template_sources:
  - path: ~/.saetr/templates           # local
  - git: https://github.com/saetr/templates  # official
  - git: https://github.com/someone/saetr-templates  # community
```

**Decision:** [ ] Implement  [ ] Skip  [ ] Defer

**Notes:**
```




```

---

### 7. Model Failover

**What OpenClaw does:**
- Supports Claude and OpenAI models
- Graceful degradation across providers
- Session can switch models without losing context

**Current Saetr state:**
- Claude Code only
- No fallback if API unavailable

**Proposed for Saetr:**

```yaml
# ~/.saetr/config.yaml
agents:
  primary: claude-code
  fallback:
    - codex        # OpenAI Codex CLI
    - aider        # aider with Claude/GPT API
    - cursor-cli   # if it exists

  fallback_triggers:
    - error: "rate_limit"
      wait: 60s
      then: retry

    - error: "api_unavailable"
      switch_to: fallback[0]

    - error: "context_exceeded"
      action: compact_and_retry
```

**Consideration:** Different agents have different capabilities. Fallback might only work for simple tasks.

**Decision:** [ ] Implement  [ ] Skip  [ ] Defer

**Notes:**
```




```

---

### 8. Real-Time Status Dashboard

**What OpenClaw does:**
- Live Canvas with A2UI framework
- Visual task management
- Interactive agent activity display

**Current Saetr state:**
- `list-projects.sh` shows container status
- No task-level visibility
- No real-time updates

**Proposed for Saetr:**

**CLI dashboard:**
```
$ saetr status --watch

┌─────────────────────────────────────────────────────────────────┐
│ SAETR STATUS                                    01:23:45 uptime │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ACTIVE TASKS                                                   │
│  ├── ENG-123  project-1  ██████████░░░░  Running tests (3/12)   │
│  ├── ENG-456  project-2  ████████████░░  Awaiting review        │
│  └── ENG-789  project-3  ██░░░░░░░░░░░░  Reading ticket         │
│                                                                 │
│  PENDING APPROVAL                                               │
│  └── ENG-999  from @aaron (Slack)  `saetr approve abc123`       │
│                                                                 │
│  RECENT COMPLETIONS                                             │
│  ├── ENG-100  PR #138 merged                        2h ago      │
│  └── ENG-101  PR #139 ready for review              4h ago      │
│                                                                 │
│  CONTAINERS                                                     │
│  ├── project-1  running   ports 3100-3109   cpu 45%  mem 2.1G  │
│  ├── project-2  running   ports 3200-3209   cpu 12%  mem 1.8G  │
│  └── project-3  running   ports 3300-3309   cpu 67%  mem 3.2G  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Web dashboard (optional):**
- Daemon serves simple web UI on `localhost:18790`
- Same info as CLI but in browser
- Accessible via Tailscale from phone

**Decision:** [ ] Implement  [ ] Skip  [ ] Defer

**Preference:** [ ] CLI only  [ ] Web only  [ ] Both

**Notes:**
```




```

---

## Implementation Phases

Based on dependencies and impact:

### Phase 2A: Daemon Foundation
- [ ] Daemon architecture
- [ ] HTTP API for triggers
- [ ] CLI client refactor (calls daemon API)
- [ ] Basic status endpoint

### Phase 2B: Security Layer
- [ ] Permission tiers
- [ ] Approval workflows
- [ ] Source authentication (Slack user verification, etc.)

### Phase 3A: External Triggers
- [ ] Slack integration
- [ ] Linear webhook
- [ ] GitHub webhook (optional)

### Phase 3B: Orchestration
- [ ] Task queue with persistence
- [ ] Inter-agent communication (event log)
- [ ] Staged workflows (implement → review → iterate)

### Phase 3C: Visibility
- [ ] CLI status dashboard
- [ ] Web dashboard (optional)
- [ ] Notifications (Slack DM on completion)

### Phase 4: Polish
- [ ] Templates registry
- [ ] Model failover
- [ ] Mobile-friendly status page

---

## Decision Summary

Fill this out after reviewing each section:

| Feature | Decision | Phase | Notes |
|---------|----------|-------|-------|
| Daemon architecture | | | |
| Multi-channel triggers | | | |
| Permission tiers | | | |
| Approval workflows | | | |
| Inter-agent communication | | | |
| Templates registry | | | |
| Model failover | | | |
| Status dashboard | | | |

---

## Open Questions

1. **Daemon language:** Bash? Python? Go? Node?
   - Bash: Consistent with current scripts
   - Python: Easy async, good libraries
   - Go: Single binary, good for daemons
   - Node: Match OpenClaw's approach

2. **State persistence:** SQLite? JSON files? Redis?
   - SQLite: Robust, queryable, single file
   - JSON: Simple, human-readable
   - Redis: Fast, but another dependency

3. **Slack integration approach:** Slack app? Webhook only? Both?
   - Slack app: Slash commands, interactive buttons
   - Webhook: Simpler, outbound only (for notifications)

4. **Review agent:** Same Claude Code? Separate tool? Human-in-loop only?
   - Could use Claude Code with different system prompt
   - Could integrate with existing review bots (CodeRabbit, etc.)
   - Could just notify human and wait

---

## References

- OpenClaw repo: https://github.com/openclaw/openclaw
- Saetr Phase 1 plan: `docs/plans/2026-01-17-saetr-phase1.md`
- Saetr design doc: `docs/design.md`
