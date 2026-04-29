# logic-cons-consumer1

APIM front-end for an **Azure Logic App (Consumption)** workflow. APIM exposes the workflow's HTTP `manual` trigger as a managed API and signs the call with the trigger's SAS shared key (stored as an APIM named value).

- **APIM path:** `/` (root — this API is mounted at the service base URL)
- **Backend:** `https://prod-199.westeurope.logic.azure.com/workflows/6d5d1c3d…c4ad7/triggers` (Logic App Consumption)
- **Subscription required:** Yes (`Ocp-Apim-Subscription-Key`)

## Operations

| Method | Operation | Summary |
|---|---|---|
| POST | `manual-invoke` | Invokes the Logic App's `manual` HTTP trigger |

OpenAPI: [openapi.json](openapi.json). Operation policies in [operations/](operations).

## Policies

### `policy.xml` (API scope)

```xml
<set-backend-service backend-id="LogicApp_logic-cons-consumer1_rg-aircrafts-app_…" />
```

Routes every operation in this API to a pre-registered **APIM Backend** entity (created automatically when the Logic App was imported through the portal). The Backend resource holds the workflow's URL and credentials, so changes (e.g., regenerated SAS keys) are managed centrally instead of in each policy.

### `operations/manual-invoke.policy.xml`

```xml
<set-method>GET</set-method>
<rewrite-uri template="/manual/paths/invoke/?api-version=2016-06-01&sp=/triggers/manual/run&sv=1.0&sig={{logic-cons-consumer1_manual-invoke_…}}" />
<set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
```

What it does:

1. **`set-method GET`** — Forces the outgoing request to the Logic App to use `GET` (regardless of how the client called APIM).
2. **`rewrite-uri`** — Rewrites the path to the Logic App's standard manual-trigger invocation URL, including the required `api-version`, `sp`, and `sv` query parameters. The `sig` parameter is filled from a **named value** (`{{logic-cons-consumer1_manual-invoke_…}}`) — that named value stores the workflow's SAS signature so the secret is never hard-coded in the policy.
3. **`set-header Ocp-Apim-Subscription-Key … delete`** — Strips the APIM subscription key before the request leaves APIM, so the Logic App never sees it.

## Notes

- The Logic App's SAS signature is the actual authentication. Rotating the workflow's access keys requires updating the named value referenced by the policy.
- Because `subscriptionRequired = true`, callers must pass an APIM subscription key to reach this API; APIM converts that into the SAS-signed call to the Logic App.
