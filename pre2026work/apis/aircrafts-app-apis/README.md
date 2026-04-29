# aircrafts-app-apis

Front-door API exposing the **aircrafts** product catalog and parts/booking operations. The backend is an **Azure Function App** (`func-aircrafts-app`).

- **APIM path:** `/aircrafts-app-apis`
- **Backend:** `https://func-aircrafts-app.azurewebsites.net/api`
- **Subscription required:** No (auth is enforced via Entra ID JWT at the operation level)
- **Description:** Operations to view a product catalog and order parts.

## Operations

| Method | Operation | Summary |
|---|---|---|
| POST | `post-createbooking` | CreateBooking |
| POST | `post-createparts` | CreateParts |
| GET | `get-funcchecktype` | FuncCheckType |
| GET | `get-readbookings` | ReadBookings (policy attached) |
| GET | `get-readparts` | ReadParts (policy attached) |

The full OpenAPI definition is in [openapi.json](openapi.json). Operation-level policies are under [operations/](operations).

## Policies

There is no API-level `policy.xml` — only the global policy and per-operation policies apply.

### `operations/get-readbookings.policy.xml`

Secures the read-bookings endpoint with **Microsoft Entra ID** and uses a **managed identity** to call the Function App.

**Inbound**

- `validate-jwt` — Requires a `Bearer` token from the tenant `29ef4a4a-…-c948b500`, with audience claim `api://contoso1media/aircrafts-apis-publisher/Scope.Read.Bookings`. Rejects with `401 Unauthorized` on failure.
- Strips `Ocp-Apim-Subscription-Key` and the caller's `Authorization` header so they are not forwarded to the backend.
- `authentication-managed-identity` — APIM's managed identity acquires a token for resource `https://func-aircrafts-app.azurewebsites.net` and APIM injects it as the new `Authorization: Bearer …` header on the backend call. This is how APIM authenticates to the Function App (e.g., when EasyAuth/AAD is enabled on the Function App).

**Outbound**

- `set-header record_count` — Reads the JSON response body, counts items in the `parts` array, and sets a `record_count` response header.
- `set-body` (Liquid template) — Re-shapes the backend response from `{ "parts": [{ seq, description, length, … }] }` into a flatter contract `{ "PARTS": [{ "CODE", "DESC", "DEPTH" }] }` for callers.

### `operations/get-readparts.policy.xml`

Same managed-identity backend pattern as above, but with stricter token requirements and no body transformation.

**Inbound**

- `validate-jwt` — Tenant `3800381b-…-cef32cf1`. Requires the **app role** claim `roles=Parts.Read` (typical for app-only / client credentials access).
- `set-header token-sub` — Custom C# policy expression that parses the incoming JWT, extracts the `sub` claim, and forwards it to the backend in a `token-sub` header (defaults to `NOAUTH` if no token, `no-claim-value` if claim missing). Useful for backend logging/audit.
- Strips `Ocp-Apim-Subscription-Key` and `Authorization`.
- `authentication-managed-identity` — Acquires a token for resource `api://648b429c-fe09-44cb-9ea9-2bb37c66a73e` (the Function App's Entra app registration) and injects it as `Authorization: Bearer …`.

**Outbound**

- Inherits global outbound only (`<base />`).

## Notes

- The two secured operations use **different tenants and audiences**, suggesting they were configured for two distinct identity scenarios (a delegated/scope-based one for bookings and an app-role one for parts).
- The Function App is reached via its managed-identity-protected app registration; APIM's system-assigned (or user-assigned) identity must be granted access to those resources/app roles.
