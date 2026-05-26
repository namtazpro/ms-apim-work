# APIs

Place OpenAPI specs here (`.json` or `.yaml` / `.yml`).

Each API listed in the root `apis` variable points at one file in this folder, for example:

```hcl
apis = {
  "aircrafts" = {
    display_name = "Aircrafts API"
    path         = "aircrafts"
    protocols    = ["https"]
    openapi_path = "../apis/aircrafts.openapi.json"
  }
}
```

Naming convention: `<api-key>.openapi.json` (or `.yaml`).
