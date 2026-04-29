# logic-cons-consumer2

Second APIM front-end for an **Azure Logic App (Consumption)** workflow. Same overall pattern as [`logic-cons-consumer1`](../logic-cons-consumer1/README.md) but mounted on a different path and with an extra outbound transformation.

- **APIM path:** `/consum2`
- **Backend:** `https://prod-15.westeurope.logic.azure.com/workflows/757cc02c…61267/triggers` (Logic App Consumption)
- **Subscription required:** Yes (`Ocp-Apim-Subscription-Key`)

## Operations

| Method | Operation | Summary |
|---|---|---|
| POST | `manual-invoke` | Invokes the Logic App's `manual` HTTP trigger |

OpenAPI: [openapi.json](openapi.json). Operation policies in [operations/](operations).

## Policies

### `policy.xml` (API scope)

```xml
<set-backend-service backend-id="LogicApp_logic-cons-consumer2_rg-aircrafts-app_…" />
```

Sends all calls through the registered **APIM Backend** entity that was created when the Logic App was imported, so the workflow URL and credentials are centrally managed.

### `operations/manual-invoke.policy.xml`

**Inbound**

- `set-method GET` — Forces the upstream call to the Logic App to use `GET`.
- `rewrite-uri` — Rewrites the request path to the Logic App's manual-trigger URL, with `api-version=2016-06-01`, `sp=/triggers/manual/run`, `sv=1.0`, and `sig` injected from the named value `{{logic-cons-consumer2_manual-invoke_…}}` (the workflow's SAS signature).
- Strips `Ocp-Apim-Subscription-Key` so the APIM subscription key is not leaked to the Logic App.

**Outbound**

- `set-header record_count2` — Reads the response body as JSON, counts the items in the `CTRIES` array, and exposes that count to the client in a `record_count2` response header.

## Notes

- Compared to `logic-cons-consumer1`, this API additionally **inspects the Logic App response** and surfaces a record count header — useful when the consumer wants to know how many rows were returned without having to parse the body.
- Like consumer1, rotating the Logic App's SAS key means updating the named value used in `rewrite-uri`.
