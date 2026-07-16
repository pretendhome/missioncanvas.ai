# Mission Canvas — Threat Model

**Nodes**: [MC-GOV-001] Data Boundary Enforcement / [MC-GOV-006] External Process Forensics
**Status**: ACTIVE (2026-07-09)
**Spec**: `dev/SPEC_EXIT_GATE_STARTUP_PROBE_2026-07-09.md`

This page states what Mission Canvas actually enforces, what it merely
steers, and what is out of scope by construction. Security guarantees
that are implied but not mechanized are worse than none — this document
exists so the boundary is written down, not assumed.

---

## 1. Enforced by mechanism

These are architectural walls. Bypassing them requires modifying the
code, not just prompting the model.

| Mechanism | What it enforces | Where |
|---|---|---|
| **Entry-gate sanitizer + dual clearance** | High-risk identifiers (SSN, case numbers, credit cards, …) are detected before classification; their presence forces local routing regardless of what the classifier says. Gate AND classifier must both clear a query for external routing. | `src/gates/entry.py`, `src/gateway/sanitizer.py` |
| **Exit-gate socket allowlist** | In-process Python `socket.create_connection` is monkeypatched; any host not on the allowlist (or a private prefix) raises `ConnectionError` and logs a BLOCKED event. | `src/gates/exit.py` |
| **Startup probe (`verify_active`)** | Activation is *proven*, not assumed: at every activation surface the gate attempts `192.0.2.1:9` (RFC 5737 TEST-NET-1 — never routable, numeric, zero DNS) and requires its own gate error to answer. A Pipeline whose firewall demonstrably isn't intercepting refuses to run (`RuntimeError`). | `src/gates/exit.py`, `src/pipeline.py` |
| **Origin gating** | Only `operator`-origin traffic trains learned weights or mints candidates. Agent (`MC_AGENT=1`), eval, and public traffic never touch the learning substrate. | `src/pipeline.py`, `src/learning.py` |
| **Schema pins** | The learning substrate is text-free by schema: PathRecord/SessionRecord field sets are frozen and tested; raw query text cannot silently enter the weight store. | `src/memory/*`, `tests/test_memory_retention.py` |
| **Candidate store scrub + promotion gate** | Candidate text fields are scrubbed at the store boundary; identifier-bearing signals are dropped; promotion and gauntlet approval refuse any candidate carrying a sensitive identifier value. | `ontology/proposals/candidate.py`, `src/gauntlet.py` |
| **Log lifecycles** | Firewall log and trace log rotate with carry-tail, archives are scanned, and `mc lens redact-queries` removes operator query text on demand. | `src/gates/exit.py`, trace rotation in memory adapter |
| **MCP Trust Boundary & Gates** | stdio local-only forever trust model; no in-protocol auth by design (R-1/R-2); side-effecting tools are refused unless launching process sets `MC_MCP_ALLOW_SIDE_EFFECTS=1`. Privileged actions require `MC_MCP_ALLOW_PRIVILEGED=1`. | `src/mcp_server.py` |

### What the startup BLOCKED line proves

At every startup, `verify_active()` deliberately lands a BLOCKED event
for host `192.0.2.1` in the firewall log. That line is per-session
evidence the gate was live when the session began. Its absence in a
session's log means the gate was never verified that session. It does
not prove the gate stayed live for the whole session (a later import
could displace the patch — health Loop 3 re-probes on every `mc health`
run to narrow that window).

## 2. Enforced by policy

These steer behavior but are not walls. A sufficiently adversarial
prompt or a misbehaving model can deviate; the mechanisms in §1 are
what contain the blast radius when that happens.

- **Lenses** (protection, legal, fiduciary, …) — shape how the model
  reasons and what it strips from responses.
- **Prompts and response-format rules** — the `[NODE-ID]` header block,
  general-principles-only answers under the legal lens.
- **Agent manuals** (`AGENTS.md`) — instructions to agents operating in
  the repo, honored by cooperation, not enforcement.

## 3. Out of scope (by construction)

The exit gate governs **in-process Python `socket.create_connection`
only**. The following bypass it entirely — not as bugs, but by the
nature of the mechanism:

- **Subprocess / child-process egress**: `git`, `curl`, `pip`, the
  Node hub, anything spawned via `subprocess` — child processes get a
  fresh, unpatched socket stack.
- **`os.system`** and shell escapes — same reason.
- **Raw sockets**: code that calls `socket.socket()` + `connect()`
  directly does not pass through `create_connection`.
- **Async HTTP clients** (`httpx.AsyncClient`, anything on the
  asyncio/anyio event loop): the event loop connects via non-blocking
  raw `sock.connect`, so an armed gate does not see these connections
  — verified empirically 2026-07-12 (an armed, probe-verified gate
  blocks a sync `httpx` GET and passes the identical async GET). This
  includes Mission Canvas's own provider pings and streaming calls.
  Compensating wall: `provider_registry.validate_provider` re-imposes
  the same allowlist at the httpx request boundary (`_egress_wall`
  hook — aborts before DNS or connect), and streaming payloads pass
  the payload-level egress walls. Closing the socket-level hole
  requires patching deeper than `create_connection` and is a
  gate-mechanism decision, not a patch.
- **DNS queries** made by the gate's own `_is_allowed` resolution step
  (`getaddrinfo`) — resolving a hostname leaks the name to the
  resolver before the allow/block decision. The startup probe avoids
  this by using a numeric address.
- **Quasi-identifiers in outbound research** ("the only bilingual
  school in Hayes Valley"): no pattern detector catches these, and we
  don't pretend one does. Sensitive-flagged queries have their
  outbound research question rebuilt from the classification tuple
  (topic-level generalization) so operator sentences never leave; for
  non-sensitive queries a quasi-identifier — a uniquely identifying
  *combination* of innocuous facts — can still exit through the
  sanitizer. Residual risk,
  named.

### Accepted risk, resolved: config/mcp_keys.yaml git-committed leak

On 2026-07-01 (commit `5d06eab3`), a configuration file containing a real operator API key (`config/mcp_keys.yaml`) was git-tracked and pushed to a public repository. This leak was the direct result of a legacy design that simulated multi-tenancy inside a local stdio MCP server using config-file keys.
Remediation: The key mechanism was completely deleted in v2. The server is now strictly local-only stdio with no in-protocol key authentication (R-1/R-2). Since the server no longer accepts or reads keys, the leaked key is structurally dead (stronger than key rotation). The file has been removed from tracking and added to config/.gitignore as a tombstone. Incident recorded in this register.

### Accepted risk, named: github.com as install infrastructure

`github.com`, `objects.githubusercontent.com`, and
`release-assets.githubusercontent.com` are allowlisted so the
consent-click Ollama installer and self-orientation clone work. This
means an adversarial prompt that achieves in-process code execution
could exfiltrate data to a repository or gist **through the allowlist**.
This is a known, accepted exfiltration surface — accepted because the
install path is first-party and the alternative (no allowlisted install
infra) breaks onboarding. Scoping these hosts to installer-only
contexts is on the backlog; until then this document is the honest
record of the trade.

### Accepted risk, named: plaintext provider keys at rest

**AR-PC1: Plaintext provider keys at rest.** providers.json stores API keys plaintext under
0600 on the operator's machine. Accepted for the local-first single-operator release.
Mitigations: 0600 enforced on every write (llm_proxy save_config) + ignition warning +
audit check; atomic writes; sanitizer strips key patterns from all outbound content;
invariant 4 bans keys from logs/errors/route reasons/MCP messages; validation errors
truncate provider responses to 100-200 chars and never echo the submitted key.
**Named follow-up (not this arc)**: OS-keychain custody (keyring/secretstorage) when
distribution scope exceeds single-operator workstations.

## 4. High-assurance deployments

If your threat model includes subprocess egress or raw sockets, the
in-process gate is not sufficient and was never claimed to be. Use
OS-level egress control — nftables/iptables rules or an egress proxy
that allowlists the same hosts — and treat the exit gate as
defense-in-depth plus audit logging, not as the perimeter.

## 5. How this composes with network-layer AI governance

Enterprise AI governance products such as WitnessAI describe their
capabilities as **Observe / Protect / Control**. Mission Canvas
implements each of those functions — at the workstation, before
reasoning, rather than inline on the network:

| WitnessAI says | MC mechanism | Where |
|---|---|---|
| Observe | traces, paths, `mc why`, `mc observe`, firewall log | `src/why.py`, `src/observe.py`, `MC_ROOT/memory/data/firewall_log.ndjson` |
| Protect | entry/exit gates + startup probe, sanitizer, dual clearance, PROTECT taint | `src/gates/`, P2/P4/P12 |
| Control | ontology triage, routing policy, origin lanes, action governance | `ontology/`, `src/routing_policy.py`, `actions/core.yaml` |

**Complementarity, not competition.** WitnessAI governs the network;
vLLM Semantic Router optimizes the inference fleet; Mission Canvas
governs the work itself — and composes with both. In an enterprise
deployment, MC's outbound calls would pass through a network gateway
like WitnessAI's and look exemplary in its logs: already classified,
already sanitized, already routed by compiled boundary. If the
deployment runs a multi-model fleet behind a semantic router, MC's
provider calls are ordinary, well-formed traffic to it. The value
claim is the bundle — pre-reasoning classification, compiled
boundaries, and a per-query audit trail operating together at the
point where the work happens.

**Why this document is not structured as O/P/C.** The
mechanism / policy / out-of-scope framing above is deliberately
stronger than an Observe/Protect/Control module map: it distinguishes
walls from steering. A module named "Protect" does not tell an
auditor whether bypassing it requires modifying code or merely
prompting a model. Sections 1–3 of this document do.

**Custody contrast.** An inline network proxy sees everything in
order to govern it — every prompt from every employee transits the
vendor's gateway. Mission Canvas inverts the custody model:
private things never reach a proxy at all. `blocks_external` content
is forced local before any network hop exists to inspect
(§1, entry-gate sanitizer + dual clearance). And per pillar 2, MC
will never ship surveillance-adjacent features — no employee
monitoring, no engagement scoring, no behavioral profiling. The
system governs the work, not the worker.
