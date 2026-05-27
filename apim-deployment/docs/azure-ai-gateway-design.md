# Azure AI Gateway — Design Guide for Shared Foundry Model Consumption

> A consolidated design note covering: what the Azure AI Gateway pattern is, how to handle TPM/RPM limits when models are shared, how to engineer for a near-zero 429 experience without PTU, and how to lay out Foundry resources and projects for 8 workload teams.

> **Note on model choice:** `gpt-4.1` is used throughout this document as an **illustrative example**. The same patterns, policies, and topology apply to any Azure OpenAI / Foundry model (e.g., `gpt-4o`, `gpt-4o-mini`, `gpt-4.1-mini`, `o3`, `o4-mini`, embedding models). Substitute deployment names, TPM/RPM ratios, and SKU availability per your actual model.

---

## 1. What is the "Azure AI Gateway"?

Azure does not ship a product literally named "AI Gateway". The pattern is built on **Azure API Management (APIM)** acting as a gateway in front of AI models, MCP tools, and agents. Microsoft refers to this capability as the **GenAI Gateway**.

APIM sits between client apps / agents and AI backends (Azure OpenAI, Azure AI Foundry models, third-party LLMs) and provides centralized **governance, security, resilience, and observability**.

### Key capabilities
- **Token rate limiting** — per-key/user TPM caps across multiple backends (`azure-openai-token-limit`)
- **Token usage metrics** — emit prompt/completion token counts to App Insights (`azure-openai-emit-token-metric`)
- **Semantic caching** — reuse responses for semantically similar prompts using embeddings + Azure Redis
- **Load balancing & circuit breaker** — spread traffic across multiple deployments/regions; fail over on 429s
- **Content safety** — integrate Azure AI Content Safety, Prompt Shields, jailbreak detection
- **Managed Identity auth** — APIM authenticates to Foundry / Azure OpenAI; no keys in code
- **MCP support** — expose APIs as MCP servers; apply rate limits/auth to MCP tools
- **OpenAPI import** — bring existing APIs under the gateway

### Typical use cases
- Multi-team / multi-tenant LLM platforms requiring quotas and chargeback
- Cost control across teams sharing Azure OpenAI capacity
- Compliance (PII filtering, audit logs) for regulated workloads
- Resiliency via multi-region failover

---

## 2. Handling Token Limits (TPM) for Shared Models

When multiple consumers share the same deployment(s), you need **fair allocation, isolation, and visibility**.

### 2.1 Use the `azure-openai-token-limit` policy
APIM's purpose-built policy enforces **Tokens-Per-Minute (TPM)** caps at the gateway, *before* the request hits the model. It estimates prompt tokens and tracks completion tokens, returning **429** when exceeded.

Limits can be scoped by any expression — typically:
- `subscription-id` → per consumer/app
- `headers["x-tenant-id"]` → per tenant
- `user-id` from JWT claim → per end user
- Product/API → per business unit

```xml
<azure-openai-token-limit
    counter-key="@(context.Subscription.Id)"
    tokens-per-minute="10000"
    estimate-prompt-tokens="true"
    remaining-tokens-header-name="x-remaining-tokens"
    tokens-consumed-header-name="x-consumed-tokens" />
```

### 2.2 Allocation strategies

| Strategy | How | When to use |
|---|---|---|
| **Hard quotas per consumer** | Different TPM per `counter-key` | Strict isolation, chargeback |
| **Tiered products** | APIM Products (Bronze/Silver/Gold) each with own policy | SaaS-style offerings |
| **Burst + sustained** | Combine `azure-openai-token-limit` (TPM) with `quota-by-key` (daily/monthly) | Prevent runaway spend |
| **Priority queues** | Route premium tenants to dedicated capacity, others to shared pool | Mixed SLAs |

### 2.3 Combine with load balancing
Pool **multiple Azure OpenAI / Foundry deployments** (across regions or PTU + PAYG) as a backend pool. APIM's circuit breaker fails over on 429s from the model, so one noisy consumer doesn't break others. The token-limit policy still enforces *logical* fairness on top.

### 2.4 Observability
Enable `azure-openai-emit-token-metric` to push token counts (dimensioned by subscription/tenant/model) to **Application Insights**:

```xml
<azure-openai-emit-token-metric namespace="AIGateway">
  <dimension name="Subscription ID" />
  <dimension name="Tenant" value="@(context.Request.Headers.GetValueOrDefault(\"x-tenant-id\",\"unknown\"))" />
  <dimension name="Model" value="@((string)context.Variables[\"deployment-id\"])" />
</azure-openai-emit-token-metric>
```

This gives you per-consumer TPM dashboards, chargeback reports, and early warning before hitting Azure OpenAI's hard model quota.

### 2.5 Reduce token pressure
- **Semantic caching** — repeated/similar prompts served from cache, not charged against TPM
- **Prompt size policies** — reject oversized prompts at the gateway
- **Model routing** — send simple requests to smaller/cheaper models

---

## 3. Handling Request Limits (RPM)

TPM alone isn't enough — Azure OpenAI enforces **both** TPM *and* RPM at the deployment level (roughly **6 RPM per 1,000 TPM**). A consumer could stay under TPM but exhaust RPM with many small requests.

### 3.1 Use `rate-limit-by-key`

```xml
<rate-limit-by-key
    calls="60"
    renewal-period="60"
    counter-key="@(context.Subscription.Id)"
    remaining-calls-header-name="x-remaining-calls" />
```

Scope it on the same key as your TPM policy so allocation is consistent.

### 3.2 Combine TPM + RPM
Whichever triggers first returns 429:

```xml
<inbound>
  <azure-openai-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="10000" />
  <rate-limit-by-key       counter-key="@(context.Subscription.Id)" calls="60" renewal-period="60" />
</inbound>
```

### 3.3 Allocation math — keep TPM and RPM aligned

| Tenant TPM | Suggested RPM (6 per 1K TPM) |
|---|---|
| 10,000 | 60 |
| 50,000 | 300 |
| 100,000 | 600 |

Sum of all tenant RPM should stay **≤ deployment RPM** (with headroom).

### 3.4 Differentiate by workload type
- **Chat / interactive** → lower RPM, higher TPM per call
- **Batch / embeddings** → higher RPM, smaller payloads
- Use different APIM Products or operation-level policies per endpoint (`/chat/completions` vs `/embeddings`).

### 3.5 Smooth bursts instead of hard-failing
- **Retry-After header** — APIM emits it automatically; Azure OpenAI SDKs honor it by default.
- **Queue-based leveling** — for non-interactive workloads, queue via Service Bus and drain at a controlled rate.
- **Backend pool + circuit breaker** — overflow to a secondary deployment/region when primary hits RPM.

---

## 4. Target Scenario — 8 Workload Teams, Single Tenant, No PTU

Goal: **8 internal teams** each running their own Foundry project for building agents share centralized models. The customer wants **no team to ever see a 429**, and is **not using PTU**.

### 4.1 Honest baseline
Without PTU you cannot mathematically guarantee zero 429s — Azure OpenAI may throttle Pay-As-You-Go even when you are below your own configured limits. The design instead **makes 429s statistically negligible** through over-provisioning, pooling, retries, and smoothing.

### 4.2 Strategy layers

#### Layer 1 — Spread quota across regions
Quota is granted **per subscription, per region, per model**. Multiple regions = multiplied capacity ceiling. Deploy `gpt-4.1` (Global Standard) in **2–3 regions** (e.g., Sweden Central, West Europe, France Central).

#### Layer 2 — Backend pool with priority + circuit breaker
```xml
<backend>
  <pool id="gpt41-pool">
    <service backend-id="foundry-swc" priority="1" weight="50" />
    <service backend-id="foundry-we"  priority="1" weight="50" />
    <service backend-id="foundry-frc" priority="2" weight="100" />
  </pool>
</backend>
```
With circuit breaker:
```xml
<circuit-breaker>
  <rule name="throttle">
    <trip-duration>30</trip-duration>
    <failure-condition>
      <status-code-range from="429" to="429" />
      <status-code-range from="500" to="599" />
      <interval>10</interval>
      <count>3</count>
    </failure-condition>
  </rule>
</circuit-breaker>
```

#### Layer 3 — Gateway-side retry (clients never see 429)
```xml
<retry condition="@(context.Response.StatusCode == 429 || context.Response.StatusCode >= 500)"
       count="4" interval="1" max-interval="8" delta="2" first-fast-retry="true">
  <forward-request buffer-request-body="true" />
</retry>
```
Combined with the backend pool, the retry hits a *different* backend on the second attempt.

#### Layer 4 — `limit-concurrency` per team (smooth, don't reject)
The key trick to avoid 429s: requests **wait** in APIM rather than be rejected.
```xml
<limit-concurrency key="@("team-" + context.Subscription.Id)" max-count="25">
  <forward-request />
</limit-concurrency>
```
Tune `max-count` per team so Σ ≤ pool concurrency × 0.85.

#### Layer 5 — Semantic cache
Typical 20–40% call deflection on agent workloads (system prompts and tool schemas repeat constantly). Frees TPM/RPM without any client changes.

#### Layer 6 — Cheaper model for routine work
Route planning, intent classification, summarization to `gpt-4.1-mini` to preserve `gpt-4.1` capacity for high-value reasoning.

---

## 5. Foundry Deployment Topology (PAYG, No PTU)

### 5.1 Key concept: where models live
- A **Foundry resource** (Azure resource, formerly "Azure AI Services" / "Azure OpenAI" account) owns **model deployments** and consumes **TPM/RPM quota**.
- A **Foundry project** is a workspace *inside* a Foundry resource for agents, threads, evaluations. It does **not** own quota.
- The 8 team projects **do not need their own model deployments** — they consume centralized models via APIM.

### 5.2 Recommended topology

```
┌────────────────────────────────────────────────────────────────┐
│                  PLATFORM / SHARED SUBSCRIPTION                 │
│                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐ │
│  │ Foundry Resource │  │ Foundry Resource │  │ Foundry Res. │ │
│  │  Sweden Central  │  │  West Europe     │  │  France Cen. │ │
│  │                  │  │                  │  │              │ │
│  │ gpt-4.1 (GS)     │  │ gpt-4.1 (GS)     │  │ gpt-4.1 (GS) │ │
│  │ text-embed-3-lg  │  │ text-embed-3-lg  │  │              │ │
│  └────────┬─────────┘  └────────┬─────────┘  └──────┬───────┘ │
│           └─────────┬───────────┴────────────────────┘         │
│                     ▼                                           │
│              ┌────────────┐                                     │
│              │   APIM     │  Pool + retry + cache + MI          │
│              │  Gateway   │                                     │
│              └─────┬──────┘                                     │
└────────────────────┼────────────────────────────────────────────┘
                     │ (single endpoint exposed)
       ┌─────────────┼─────────────┐ ... (8 teams)
       ▼             ▼             ▼
  ┌─────────┐   ┌─────────┐   ┌─────────┐
  │ Team 1  │   │ Team 2  │   │ Team 8  │
  │ Foundry │   │ Foundry │   │ Foundry │
  │ Project │   │ Project │   │ Project │
  │ (agents)│   │ (agents)│   │ (agents)│
  └─────────┘   └─────────┘   └─────────┘
```

### 5.3 Step 1 — Shared Foundry resources
Create **2–3 Foundry resources** in different regions, typically inside **one shared platform subscription**.

> **Single subscription is sufficient.** Azure OpenAI quota is granted per **(subscription × region × model × SKU)** — so deploying the same model in multiple **regions** within one subscription already gives you independent quota pools. Multiple subscriptions are only needed if you (a) hit the per-subscription regional quota ceiling and Microsoft denies further increases, (b) need finance-level chargeback at subscription granularity, or (c) require strict blast-radius isolation (e.g., prod vs non-prod).

Why this works:
- Quota is per region (per subscription) → 3 regions ≈ 3× TPM ceiling, all in the same subscription
- Regional resilience (one region down → others absorb)
- PAYG pricing identical across regions for the same SKU

Region picks (verify availability for gpt-4.1):
- **Sweden Central** (primary)
- **West Europe** (spillover)
- **France Central** or **Switzerland North** (optional third leg)

> If EU data residency matters, choose **Data Zone Standard** (EU data zone) instead of Global Standard so traffic stays in the EU while still pooling capacity.

**Recommended single-subscription layout:**
```
ONE PLATFORM SUBSCRIPTION
├── rg-platform-ai-shared
│    ├── foundry-swc      (gpt-4.1 GS, embedding GS)
│    ├── foundry-we       (gpt-4.1 GS, embedding GS)
│    ├── foundry-frc      (gpt-4.1 GS) — optional
│    ├── apim-shared      (gateway, MI, policies, products)
│    ├── appi-shared      (App Insights for token metrics)
│    └── redis-shared     (semantic cache backend, optional)
│
└── rg-team-1 … rg-team-8  (Foundry projects, agent storage)
```
Teams get their own **resource groups** for RBAC and cost-tracking, while sharing the centrally-deployed models.

### 5.4 Step 2 — Deploy models in each region

| Model | SKU | Purpose |
|---|---|---|
| `gpt-4.1` | Global Standard (or Data Zone Standard) | Agent reasoning |
| `text-embedding-3-large` | Global Standard | RAG / memory |
| `gpt-4.1-mini` (optional) | Global Standard | Cheap planner/router |

Important:
- **Request quota increases upfront** via Azure portal → Quotas → support ticket. Default quotas are small; target **hundreds of thousands of TPM per region**.
- Use **identical deployment names across regions** (e.g., `gpt-4.1`) so APIM can swap backends without rewriting paths.

### 5.5 Step 3 — Wire APIM to the Foundry resources

For each Foundry resource, register an APIM Backend:
```
foundry-swc   → https://foundry-swc.cognitiveservices.azure.com/openai
foundry-we    → https://foundry-we.cognitiveservices.azure.com/openai
foundry-frc   → https://foundry-frc.cognitiveservices.azure.com/openai
```
Group into a load-balanced pool with circuit breaker (see §4.2 Layer 2).

Authenticate APIM → Foundry with **Managed Identity** + `Cognitive Services OpenAI User` role on each Foundry resource. No API keys.

### 5.6 Step 4 — Connect each team's Foundry project to APIM

#### Pattern A — Custom model connection (recommended for agents)
In each team's Foundry project:
1. **Management center → Connected resources → + New connection → Serverless model** (or "Custom keys" — name varies by portal version).
2. Set:
   - **Target URI**: `https://<your-apim>.azure-api.net/openai`
   - **Key**: the team's APIM **subscription key** (one per team = one identity for metering)
   - **Model name**: `gpt-4.1`
3. The connection becomes selectable when defining an agent's model.

Every inference call from the agent now flows through APIM.

#### Pattern B — Direct SDK calls
For custom code:
```python
client = AzureOpenAI(
    azure_endpoint="https://<your-apim>.azure-api.net",
    api_key="<team-apim-subscription-key>",
    api_version="2024-10-21",
)
```

### 5.7 What lives in each team's Foundry project
**Yes:** Agents (definitions, instructions, tools), threads/runs, connections (APIM + team-specific tools like AI Search), evaluations, prompt flows, traces.
**No:** Model deployments, quota allocation.

Each team project can sit in **its own resource group** (and optionally its own subscription) for cost segregation while still consuming centrally-pooled models. A single shared subscription for everything is also fully supported.

### 5.8 Agent-specific tuning
Foundry agents tend to make **bursty multi-call patterns** (planner → tool → planner → tool):
- Give the agent loop a longer client timeout so APIM has room to retry/queue silently.
- Cache **embeddings** aggressively — agents re-embed identical tool descriptions constantly.

---

## 6. Networking — Private Connectivity Across Regions

Foundry resources can run behind VNets in a single subscription across multiple regions. The design has a few important nuances.

### 6.1 Each region needs its own VNet
VNets are **regional resources** — one VNet cannot span Sweden Central + West Europe + France Central. Pattern:

```
Sub: platform
├── vnet-hub-swc       (Sweden Central) — APIM + shared services
├── vnet-spoke-swc     (Sweden Central) — foundry-swc private endpoint
├── vnet-spoke-we      (West Europe)    — foundry-we   private endpoint
└── vnet-spoke-frc     (France Central) — foundry-frc  private endpoint
```
Connect them with **VNet peering** (global peering works cross-region) or **Azure Virtual WAN** at scale.

### 6.2 Foundry private networking — two options

**Option A: Private Endpoints on each Foundry resource (most common)**
- Each Foundry resource gets a Private Endpoint in the spoke VNet of its region.
- Public network access disabled on the resource.
- DNS resolved via Azure Private DNS Zone `privatelink.cognitiveservices.azure.com` (one zone, linked to all VNets).

**Option B: Foundry network injection / managed VNet**
- For where the **agent runtime** runs, separate from model endpoint privacy.
- Optional for this design (centralized models + per-team projects).

### 6.3 APIM placement

**Pattern 1 — APIM in one region (recommended for most cases)**
- APIM deployed in **internal VNet mode** (Premium) or **Standard v2 with VNet integration**.
- Lives in the hub VNet (e.g., Sweden Central).
- Reaches foundry-we / foundry-frc via peered spokes and their Private Endpoints.
- ✅ Simple, single gateway URL. ❌ APIM itself is single-region.

```
       ┌─────────────────────────────┐
       │ APIM (Sweden Central)       │
       │ Internal VNet mode          │
       └──┬──────────┬──────────┬────┘
          │ peering  │ peering  │ peering
   ┌──────▼───┐ ┌────▼─────┐ ┌──▼───────┐
   │ PE       │ │ PE       │ │ PE       │
   │ foundry- │ │ foundry- │ │ foundry- │
   │ swc      │ │ we       │ │ frc      │
   └──────────┘ └──────────┘ └──────────┘
```

**Pattern 2 — APIM multi-region (Premium only)**
- Primary + secondary gateway units across regions, each in its own VNet.
- Front Door / Traffic Manager in front for a single anycast URL.
- ✅ Survives regional APIM outage. ❌ More complex; usually overkill — backend pooling already handles model-region failures.

### 6.4 Cross-region traffic — performance & cost
When APIM in Sweden Central calls foundry-we / foundry-frc:
- **Latency:** typically 15–30 ms intra-EU; negligible vs. LLM inference time.
- **Egress cost:** ~$0.02/GB inbound + outbound on peering — a few cents per million tokens.
- **Bandwidth:** No practical limit at LLM call volumes.

> **Data residency caveat:** Global Standard deployments may route inference outside the deployment region by Microsoft. The Private Endpoint pins the *control plane*, not where the model actually runs. Use **Data Zone Standard** (EU only) if you need traffic to stay in the EU — fully compatible with private endpoints.

### 6.5 DNS — the #1 source of bugs

- Use **one Azure Private DNS Zone** for `privatelink.cognitiveservices.azure.com`.
- **Link it to every VNet** (hub + all spokes in all regions).
- Each Private Endpoint auto-registers an A record (e.g., `foundry-swc → 10.1.0.4`, `foundry-we → 10.2.0.4`, `foundry-frc → 10.3.0.4`).
- Public DNS for `foundry-we.cognitiveservices.azure.com` CNAMEs into the privatelink zone automatically.
- Also link `privatelink.azure-api.net` (for APIM if internal mode) to all VNets that need to call APIM privately.
- For **on-premises** clients, set conditional forwarders for `privatelink.cognitiveservices.azure.com` → 168.63.129.16 via a private DNS resolver or **DNS Private Resolver** inbound endpoint.

### 6.6 Egress from team Foundry projects
If team projects are network-restricted:
- Agents call APIM → APIM is private → teams must reach the APIM private IP.
- **Foundry standard agents** (Microsoft-managed compute): outbound flows via Microsoft backbone — just ensure private DNS resolves correctly.
- **Bring-your-own-compute** agents: peer the team VNet to the hub.

### 6.7 Recommended network design (one subscription, three regions)

```
┌─────────────────────────── PLATFORM SUBSCRIPTION ────────────────────────────┐
│                                                                              │
│   Sweden Central (hub)              West Europe                France Central │
│  ┌─────────────────────┐         ┌────────────────┐         ┌──────────────┐ │
│  │ vnet-hub-swc        │◄═══════►│ vnet-spoke-we  │◄═══════►│vnet-spoke-frc│ │
│  │                     │ peering │                │ peering │              │ │
│  │ • APIM (Internal)   │         │ • PE foundry-we│         │ • PE foundry-│ │
│  │ • Azure Firewall    │         │                │         │   frc        │ │
│  │ • Private DNS link  │         │ • Private DNS  │         │ • Private DNS│ │
│  │ • PE foundry-swc    │         │   link         │         │   link       │ │
│  │ • PE Redis (cache)  │         │                │         │              │ │
│  │ • PE App Insights   │         │                │         │              │ │
│  └─────────────────────┘         └────────────────┘         └──────────────┘ │
│                                                                              │
│   Private DNS Zone: privatelink.cognitiveservices.azure.com (linked to all) │
│   Private DNS Zone: privatelink.azure-api.net (linked to all)               │
└──────────────────────────────────────────────────────────────────────────────┘
                              ▲
                              │ private (PE / VPN / ExpressRoute)
                              │
            ┌──────────────────┴──────────────────┐
            │       8 Team Foundry projects        │
            │  (can be in same sub or others)      │
            └─────────────────────────────────────┘
```

### 6.8 APIM SKU choice

| Need | APIM SKU |
|---|---|
| Internal VNet mode (fully private gateway) | **Premium** or **Standard v2** with VNet integration |
| Multi-region gateways | **Premium** only |
| Lowest-cost private | **Standard v2** |
| Dev/test, public OK | Developer / Basic v2 |

**Premium** is the typical pick for shared enterprise platforms; **Standard v2** is a viable cheaper alternative if you don't need multi-region or Developer Portal customization.

### 6.9 Networking summary
- ✅ One subscription, three regional VNets, peered.
- ✅ Each Foundry resource → Private Endpoint in its regional spoke.
- ✅ Single shared Private DNS Zone for cognitiveservices, linked everywhere.
- ✅ APIM in the hub (Premium or Standard v2, internal mode).
- ✅ Cross-region peering for backend pool — latency/cost negligible.
- ⚠️ Use Data Zone Standard if traffic must stay in the EU.
- ⚠️ DNS configuration is the #1 source of bugs — link the privatelink zone everywhere.

---

## 7. End-to-End Deployment Checklist

### Platform team (one-time)
- [ ] Decide regions (e.g., Sweden Central + West Europe + France Central)
- [ ] Create 2–3 Foundry resources in a platform subscription
- [ ] Request quota increases per region (target ≥ 2× peak demand)
- [ ] Deploy `gpt-4.1` (Global Standard or Data Zone Standard) in each region with the **same deployment name**
- [ ] Deploy embedding model in each region
- [ ] Create APIM instance (Standard v2 or Premium for VNet)
- [ ] Enable system-assigned Managed Identity on APIM
- [ ] Grant APIM MI `Cognitive Services OpenAI User` on each Foundry resource
- [ ] Register each Foundry resource as an APIM Backend
- [ ] Group backends into a pool with priority + circuit breaker
- [ ] Apply policies: MI auth, semantic cache, retry, per-team concurrency limit, token metrics
- [ ] Wire App Insights for token metric dimensions (Team, Model, Operation)

### Per team (×8)
- [ ] Create APIM Subscription (one per team) for identity & metering
- [ ] Create / claim a Foundry project (own RG/subscription if desired)
- [ ] Add a Connection in the project pointing to the APIM endpoint with the team's subscription key
- [ ] Build agents using that connection as the model source
- [ ] Validate: agent runs end-to-end; App Insights shows per-team token metrics

### Ongoing
- [ ] Monitor per-team TPM/RPM, 429 rate (target near 0%)
- [ ] Re-balance per-team `limit-concurrency` as workloads grow
- [ ] Track semantic cache hit ratio (target ≥ 20%)
- [ ] Periodically request quota increases as aggregate demand grows
- [ ] Re-evaluate PTU once steady-state usage justifies the commitment

---

## 8. Key Take-aways

1. **APIM is the AI Gateway.** All governance/control lives in policies, not in the model resource.
2. **Centralize models, federate projects.** Foundry projects belong to teams; model deployments belong to the platform.
3. **Multiple regions ≈ poor-man's PTU.** Without PTU, geographic pooling + retry + concurrency limits is the path to near-zero 429.
4. **Smooth, don't reject.** Prefer `limit-concurrency` over `rate-limit-by-key` when the goal is invisible enforcement.
5. **Cache aggressively.** Semantic cache + embedding cache often reclaim 20–40% of capacity for agent workloads.
6. **Observe per team.** App Insights with team/model/operation dimensions enables fairness tuning and chargeback.
7. **Be honest about SLAs.** Without PTU there is no hard guarantee of zero throttling — but the design above typically achieves <0.01% post-retry 429 rates.
