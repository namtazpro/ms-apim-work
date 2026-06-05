| Criterion | Opt 1 — APIM everywhere | Opt 2 — No APIM (direct/thin-proxy) | Opt 3 — Conditional/hybrid Only in target cases| AlwaysOn— Layered MS plane |
|---|---|---|---|---|
| 1. Central governance & identity | ✓ one plane, but key-based | ✗ DIY per division | ◑ APIM where it pays ie enable multiple protocol for single agent | **✓** Entra Agent ID across all clouds |
| 2. Global token/rate-cap fidelity †| ✓ via existing LLM-fronting APIM | ✓ via existing LLM-fronting APIM | ✓ via existing LLM-fronting APIM | ✓ via existing LLM-fronting APIM |
| 3. Observability / audit / chargeback | ✓ gateway logs (Azure only) | ✓ gateway at model level  | ◑ mixed | **✓** gateway at model level + **Sentinel/Purview** audit |
| 4. Content safety / PII / residency | ◑ harm yes, **PII/DLP no** | federated for the agent | ◑ where APIM sits | **✓** Content Safety + **Purview** DLP |
| 5. Non-Azure reach | ◑ self-hosted gaps; **✗ air-gap** | ◑ NA | ◑ depends on placement | ◑ Entra/Defender reach off-Azure, but **stops at air-gap (D5)** |
| 6. Latency & streaming | ✗ hop on every call | ✓ lowest latency | ✓ direct where it matters | ✓ inline only where needed |
| 7. Cost & operational complexity | ✗ APIM cost and Ops Cost | ✓ lowest | ◑ moderate | ✓ Might already included licensing + integration |
| 8. Reliability / blast radius | ✗ fleet-wide SPOF | ✓ no central SPOF | ◑ contained | ◑ out-of-band controls reduce SPOF |
| 9. Discovery & developer experience | ◑ catalog, slow onboarding | ✗ defer on Agent 365 | ◑ mixed | **✓** Defender/Purview shadow-AI + API Center |
| **Regulated-domain fit (D3/D4)** | ✓ | ✗ | ✓ | **✓ (best)** |
| **Latency-critical fit (D1/D2 loops)** | ✗ | ✓ | ✓ | ✓ |
| **Air-gapped Defence fit (D5)** | ✗ unusable | ◑ self-contained only | ◑ self-contained only | ✗ suite stops at air-gap |
| **Controls ALL agents (incl. non-Azure)** | ✗ multiple control plane | ✗ Agent 365 | ✗ Agent 365 | **◑ closest** (boundary + telemetry for 3P/air-gap) |






