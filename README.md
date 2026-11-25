# OrganicServer
The goal of this project is to safely explore the power of agentic AI for server maintenance.

**OrganicServer** is a Git-based operational harness, prompt framework, and state repository designed to be cloned onto a fresh **Debian** installation. Instead of relying on opaque, one-off shell commands, it gives an agentic AI (such as OpenCode, Claude Code, or local LLM agents) a strict set of rules, architectural context, and safety guardrails to bootstrap, configure, and maintain the system over time.

The server grows *organically*: every configuration change, service deployment, and troubleshooting step is audited, applied declaratively where possible, and tracked via atomic Git commits.

---

## Core Principles

1. **Context-First Execution:** The agent must read `AGENTS.md` and the current system state before proposing or executing any command.
2. **Human-in-the-Loop for Critical Paths:** Firewall rules, SSH daemon changes, disk partitioning, and network interface modifications require explicit human approval before execution.
3. **Reversibility & Backups:** Configuration files are backed up or tracked in Git *before* modification. Destructive operations require a verified rollback plan.
4. **Atomic Documentation:** Every completed task ends with an updated state file and a clean, descriptive Git commit explaining *what* changed and *why*.

---

## Repository Structure

```text
OrganicServer/
├── AGENTS.md               # Primary system prompt, rules, and operational boundaries for the AI
├── README.md               # Project overview and bootstrap instructions
├── .ai/
│   ├── CONTEXT.md          # Current hardware specs, network topology, and active services
│   └── RUNBOOK.md          # Standard operating procedures (updates, backups, recovery)
├── manifests/              # Declarative configs, Docker Compose stacks, systemd units
├── scripts/                # Idempotent helper and audit scripts (read-only checks, backups)
└── logs/                   # Post-mortem notes and major maintenance milestones