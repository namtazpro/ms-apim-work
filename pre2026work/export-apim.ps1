# Exports APIs and policies from APIM to disk.
# Layout:
#   global-policy.xml
#   apis/<api>/api.json
#   apis/<api>/openapi.json
#   apis/<api>/policy.xml
#   apis/<api>/operations/<op>.policy.xml
#   products/<product>/policy.xml

[CmdletBinding()]
param(
    [string]$ResourceGroup = 'rg-aircrafts-app',
    [string]$ServiceName   = 'apim-contoso1media',
    [string]$OutputRoot    = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$ApiVersion = '2022-08-01'

$SubscriptionId = az account show --query id -o tsv
$Token = az account get-access-token --resource https://management.azure.com --query accessToken -o tsv
$Headers = @{ Authorization = "Bearer $Token" }
$ServiceBase = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ServiceName"

function Save-File {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Try-Get {
    param([string]$Url)
    try { return Invoke-RestMethod -Uri $Url -Headers $Headers -ErrorAction Stop } catch { return $null }
}

function Save-PolicyXml {
    param([string]$ResourcePath, [string]$OutFile)
    $url = $ServiceBase
    if ($ResourcePath) { $url += "/$ResourcePath" }
    $url += "/policies/policy?api-version=$ApiVersion&format=rawxml"
    $resp = Try-Get -Url $url
    if ($resp -and $resp.properties.value) {
        Save-File -Path $OutFile -Content $resp.properties.value
        return $true
    }
    return $false
}

function Save-OpenApi {
    param([string]$ApiName, [string]$OutFile)
    $url = "$ServiceBase/apis/$ApiName" + "?format=openapi%2Bjson&export=true&api-version=$ApiVersion"
    $resp = Try-Get -Url $url
    if ($resp -and $resp.value) {
        $json = $resp.value | ConvertTo-Json -Depth 50
        Save-File -Path $OutFile -Content $json
        return $true
    }
    return $false
}

Write-Host "Exporting from $ServiceName ($ResourceGroup) -> $OutputRoot"

if (Save-PolicyXml -ResourcePath '' -OutFile (Join-Path $OutputRoot 'global-policy.xml')) {
    Write-Host "  saved global-policy.xml"
}

$apis = az apim api list --resource-group $ResourceGroup --service-name $ServiceName -o json | ConvertFrom-Json
foreach ($api in $apis) {
    $apiName = $api.name
    Write-Host "  API: $apiName"
    $apiDir = Join-Path $OutputRoot "apis/$apiName"
    New-Item -ItemType Directory -Path $apiDir -Force | Out-Null

    $api | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $apiDir 'api.json') -Encoding UTF8

    if (Save-OpenApi -ApiName $apiName -OutFile (Join-Path $apiDir 'openapi.json')) {
        Write-Host "    saved openapi.json"
    }
    if (Save-PolicyXml -ResourcePath "apis/$apiName" -OutFile (Join-Path $apiDir 'policy.xml')) {
        Write-Host "    saved policy.xml"
    }

    $ops = az apim api operation list --resource-group $ResourceGroup --service-name $ServiceName --api-id $apiName -o json | ConvertFrom-Json
    foreach ($op in $ops) {
        $opName = $op.name
        if (Save-PolicyXml -ResourcePath "apis/$apiName/operations/$opName" -OutFile (Join-Path $apiDir "operations/$opName.policy.xml")) {
            Write-Host "    saved operations/$opName.policy.xml"
        }
    }
}

$products = az apim product list --resource-group $ResourceGroup --service-name $ServiceName -o json 2>$null | ConvertFrom-Json
foreach ($prod in $products) {
    $prodName = $prod.name
    if (Save-PolicyXml -ResourcePath "products/$prodName" -OutFile (Join-Path $OutputRoot "products/$prodName/policy.xml")) {
        Write-Host "  Product policy: $prodName"
    }
}

Write-Host "Done."
