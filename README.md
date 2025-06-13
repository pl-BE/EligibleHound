# 🧩 Azure AD Role Assignments to BloodHound (Neo4j)

This PowerShell script adds **role assignment edges** from Azure AD (Entra ID) to **BloodHound**'s Neo4j database. It allows analyzing "eligible" assignments from EntraID Privileged Identity Management (PIM) such as **Global Administrator** roles.

Edges created:

- `AZGlobalAdminEligible`
- `AZRoleEligible`

Supports:
- ✅ Full JSON export from AzureHound (recommended for object IDs)
- ✅ Lightweight CSV-only mode (for large JSON files or memory-constrained environments)

---

## 📂 Input Files

### 🔸 CSV Export (required)

Export from Entra ID PIM assignment report with at least:

| Assignment State | Role Name            | PrincipalName                        |
|------------------|----------------------|--------------------------------------|
| Eligible         | Global Administrator | user@example.onmicrosoft.com         |

Only **"Eligible"** assignments are processed.

---

### 🔸 AzureHound JSON Export (optional)

Required for standard mode (default), where object IDs are extracted from JSON.

---

## 🚀 Usage

### ▶️ Standard Mode (JSON is loaded)

```powershell
.\Script.ps1 -CsvPath .\export_example.csv -JsonPath .\azurehound_example.json
```

### 💾 Low-Memory Mode (CSV-only, no JSON parsing)

```powershell
.\Script.ps1 -CsvPath .\export_example.csv -LowMemoryMode -TenantId "6c12b0b0-b2cc-4a73-8252-0b94bfca2145"
```

> ⚠️ `-TenantId` is **required** when using `-LowMemoryMode`.

### Help

```powershell
Get-Help .\Script.ps1 -Detailed
```

---

## ⚙️ Parameters

| Parameter        | Description                                                                 |
|------------------|-----------------------------------------------------------------------------|
| `-CsvPath`       | Path to the CSV export from EntraID. Default: `export_example.csv`         |
| `-JsonPath`      | Path to the AzureHound JSON file. Default: `azurehound_example.json`       |
| `-LowMemoryMode` | Skips loading the JSON file; works only with CSV + `-TenantId`.            |
| `-TenantId`      | Azure Tenant ID used in LowMemoryMode.                                     |
| `-Neo4jUrl`      | Neo4j transactional Cypher endpoint. Default: `http://localhost:7474/...`  |
| `-Neo4jUser`     | Username for Neo4j auth. Default: `neo4j`                                  |
| `-Neo4jPassword` | Password for Neo4j auth. Default: `bloodhoundcommunityedition`             |

---

## 🧠 BloodHound Cypher Queries

Use the following example queries in the BloodHound interface to view inserted edges:

### 🔍 Eligible and Active Global Administrator role assignments

```cypher
MATCH (u:AZUser)-[r]->(role:AZRole)
WHERE role.displayname = "Global Administrator" AND type(r) IN ["AZHasRole", "AZRoleEligible"]
RETURN u, r, role
LIMIT 1000
```

### 🔍 All Global Administrators (including Eligible)

```cypher
MATCH (a)-[r]->(b)
WHERE type(r) = "AZGlobalAdminEligible" OR type(r) = "AZGlobalAdmin"
RETURN a, r, b
LIMIT 1000
```

---

## 📦 Example Output (in Console)

```text
Loading CSV from .\roles.csv
Loading JSON from .\azurehound.json
Created AZGlobalAdminEligible edge: cbailey@phantomcorp.onmicrosoft.com -> Global Administrator
Created AZRoleEligible edge: cbailey@phantomcorp.onmicrosoft.com -> Global Administrator

```

---

## 🛠️ Requirements

- PowerShell 5.1+ or PowerShell Core
- Neo4j instance running with BloodHound schema loaded
- API endpoint: Neo4j must expose HTTP Cypher endpoint (default is `:7474`)

---

## 🧪 Examples

```powershell
# With JSON input
.\Script.ps1 -CsvPath .\export_example.csv -JsonPath .\azurehound_example.json

# CSV-only mode (low memory)
.\Script.ps1 -CsvPath .\export_example.csv -LowMemoryMode -TenantId "6c12b0b0-b2cc-4a73-8252-0b94bfca2145"

# Get help
Get-Help .\Script.ps1 -Detailed
```

---

## 🛡️ Disclaimer

This script modifies data in Neo4j. Use with caution in production environments. Backup your graph database before performing batch inserts.
