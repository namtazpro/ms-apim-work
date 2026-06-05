---
title: "AI Gateway meeting digest — 4 June 2026"
description: "Digest of the AI Gateway transcript covering whether to front agents, MCP, and LLMs with APIM, including the recommended position (option 2 + option 3) and supporting rationale."
ms.date: 2026-06-04
ms.topic: concept
keywords: [APIM, AI Gateway, A2A, MCP, agents, Foundry, Agent 365, governance]
estimated_reading_time: 5
---

## Meeting metadata

- Source: `AI Gateway (2).docx` (raw transcript also in `AI Gateway (2).txt`)
- Date / duration: 4 June 2026, 11:36am UK, 22m 18s
- Topic: Should we put Azure API Management (APIM) in front of **LLMs**, **MCP servers**, and **agents**?

## Framing — the four options on the table

| # | Option | Meaning |
|---|---|---|
| 1 | APIM everywhere | APIM fronts every LLM, every MCP server, and every agent |
| 2 | No APIM | APIM is not used to front anything (still implied for LLM, see below) |
| 3 | Targeted APIM | APIM fronts agents only for **compatibility / extensibility** (not governance), case by case |
| 4 | "Always on" Microsoft plane | Agent 365, Defender for AI, Purview, Sentinel — not an option, it is always present and used as the reference for the criteria column |

> Option 4 was dropped from the options list because it is a constant, not a choice. It became the "always on" Microsoft control plane column used to evaluate the other three.

## Agreed positions (locked in during the call)

1. **LLM → fronted by APIM. Agreed.**
   Justification: PTU sharing / cost control benefits. No debate.
2. **MCP → fronted by APIM. Agreed.**
3. **Agents → still an open question**, but the preferred direction is:
   - **Primary: Option 2 — do NOT systematically front agents with APIM.**
   - **Fallback: Option 3 — use APIM only as a targeted extensibility layer** (e.g., when a third-party or Foundry-hosted agent does not natively expose A2A and you need to wrap it).
   - Stated preference in the call: *"option 2, with option 3 in the back."* Agreement that A2A on APIM is hard to recommend with current maturity.

## Why not put APIM in front of agents

### Governance and identity already live elsewhere

- For authentication / authorization of agent-to-agent calls, the control plane should be **Agent 365 + Entra ID**, not APIM.
- Putting APIM in the middle either:
  - duplicates the control plane (if you use API keys), or
  - piggybacks Entra anyway (if you use tokens) → adds no value.

### Observability gain is partial

- APIM only sees the traffic that flows through it. Agents talking via M365 internals (Copilot, Copilot CLI / SDK, etc.) bypass APIM entirely → coverage is incomplete by definition.
- Therefore "central logging" is not a strong enough reason on its own to front agents.

### Stateful workloads are the real gotcha

- LLMs are stateless → easy to gateway.
- Agents are **stateful** → unclear how state survives across multiple APIM instances or how APIM should behave when the agent maintains long-running sessions.
- This is the structural reason agent fronting is not yet mature.

### Throttling on agents is the wrong layer

- The LLM behind the agent is already throttled via the LLM-side APIM policies.
- Throttling agents themselves adds little marginal value.

### Foundry will close the gap

- The current "good" reason to front a Foundry-hosted agent with APIM is to **expose it as A2A** when Foundry does not yet do it natively.
- Microsoft has signalled Foundry will support this directly → that justification will disappear.

## Why MCP is treated differently from agents

- MCP servers are **stateless / API-shaped** (closer to LLMs than to agents).
- Wrapping them with APIM gives the standard APIM benefits (auth, throttling, observability) without the stateful-session complications agents have.
- Hence: APIM in front of MCP is fine and recommended.

## Compatibility / SDK caveat (LLM side)

- Some Microsoft and third-party SDKs (notably the **GitHub Copilot SDK** and some Foundry SDKs) acquire tokens with audience `cognitiveservices` and target Foundry endpoints directly.
- They will *not necessarily* route cleanly through APIM (audience mismatch).
- Action: flag SDK compatibility as a column / risk in the comparison table — even for the LLM tier, "APIM in front of the model" is not 100% universal.

## When option 3 (targeted APIM on an agent) still makes sense

Use APIM as an **extensibility / protocol-adaptation layer**, not as a governance layer, when:

- A Foundry agent exposes only its Response API (no A2A) and you want to publish it as A2A externally.
- A third-party agent (e.g., ServiceNow) exposes only one protocol (MCP, REST, …) and you need to adapt it to A2A or another protocol.
- Note: the moment the upstream platform supports A2A natively, drop the APIM wrapper.

## Concrete follow-ups

- [ ] Add a column to the options comparison table for **"SDK compatibility"** (Copilot SDK, Foundry SDKs, third-party).
- [ ] Add a row / note: A2A in APIM today is **essentially proxying the agent card** — minimal value-add, no real policy surface yet.
- [ ] Update the AI Gateway design doc (`apim-deployment/docs/azure-ai-gateway-design.md`) to reflect:
  - LLM → APIM: yes
  - MCP → APIM: yes
  - Agents → APIM: no by default; targeted (option 3) only for protocol adaptation
  - Identity / governance for agents → Agent 365 + Entra, not APIM
- [ ] Re-evaluate the "expose Foundry agent as A2A via APIM" pattern once Foundry ships native A2A support.

## Open questions left at end of call

- Exhaustive list of Microsoft tooling that does **not** play well with APIM in front of the LLM (Copilot SDK, M365 Copilot internals, etc.) — needs an inventory.
- What APIM A2A surface actually exposes today beyond the agent card and a passthrough policy slot — needs hands-on validation before recommending option 3 broadly.
