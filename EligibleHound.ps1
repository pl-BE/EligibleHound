<#
.SYNOPSIS
Getting eligible role assignments from EntraID/Azure into BloodHound.

.DESCRIPTION
This script creates BloodHound-compatible edges in Neo4j such as
AZGlobalAdminEligible and AZRoleEligible. It uses data from a CSV
export of Azure AD role assignments, and optionally a JSON export
from AzureHound for objectid mapping.

In low-memory environments, or when handling large AzureHound exports,
the script can be run in LowMemoryMode,
which avoids loading the AzureHound JSON file entirely and relies
solely on PrincipalName, Role Name, and a user-specified TenantId.

.PARAMETER CsvPath
Specifies the path to the role assignment CSV file.
Default: export_example.csv

.PARAMETER JsonPath
Specifies the path to the AzureHound JSON file.
Default: azurehound_example.json

.PARAMETER Neo4jUrl
The URL of the Neo4j transactional Cypher endpoint.
Default: http://localhost:7474/db/neo4j/tx/commit

.PARAMETER Neo4jUser
The username for Neo4j authentication.
Default: neo4j

.PARAMETER Neo4jPassword
The password for Neo4j authentication.
Default: bloodhoundcommunityedition

.PARAMETER LowMemoryMode
Enables processing without loading the AzureHound JSON file.
Requires -TenantId to be specified.

.PARAMETER TenantId
Specifies the Azure tenant ID to use when running in LowMemoryMode.

.INPUTS
None. This script does not accept pipeline input.

.OUTPUTS
None. Outputs are written to the console and to the Neo4j database.

.EXAMPLE
PS> .\Script.ps1 -CsvPath .\export_example.csv -JsonPath .\azurehound_example.json

.EXAMPLE
PS> .\Script.ps1 -CsvPath .\export_example.csv -LowMemoryMode -TenantId "6c12b0b0-b2cc-4a73-8252-0b94bfca2145"

.EXAMPLE
PS> Get-Help .\Script.ps1 -Detailed

#>

# Validate required parameters in LowMemoryMode

param (
    [string]$CsvPath = "export_example.csv",
    [string]$JsonPath = "azurehound_example.json",
    [string]$Neo4jUrl = "http://localhost:7474/db/neo4j/tx/commit",
    [string]$Neo4jUser = "neo4j",
    [string]$Neo4jPassword = "bloodhoundcommunityedition",
    [switch]$LowMemoryMode,
    [string]$TenantId
)

if ($LowMemoryMode -and (-not $TenantId)) {
    Write-Error "In LowMemoryMode, the TenantId must be specified."
    exit
}

# Load and filter CSV
Write-Host "Loading CSV from $CsvPath"
$csv = Import-Csv -Path $CsvPath -Delimiter ";" | Where-Object { $_."Assignment State" -eq "Eligible" }

# If not in LowMemoryMode, load the JSON file and build lookup tables
$roleMap = @{}
$userMap = @{}
$tenantMap = @{}

if (-not $LowMemoryMode) {
    Write-Host "Loading JSON from $JsonPath"
    $json = Get-Content $JsonPath -Raw | ConvertFrom-Json

    foreach ($entry in $json.data) {
        switch ($entry.kind) {
            "AZRole"   { $roleMap[$entry.data.displayName] = $entry.data }
            "AZUser"   { $userMap[$entry.data.userPrincipalName] = $entry.data }
            "AZTenant" { $tenantMap[$entry.data.tenantId] = $entry.data }
        }
    }
}

# Prepare Neo4j API request headers
$headers = @{
    Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${Neo4jUser}:${Neo4jPassword}"))
    "Content-Type" = "application/json"
}

foreach ($entry in $csv) {
    $roleName = $entry."Role Name"
    $principalName = $entry.PrincipalName

    if ($LowMemoryMode) {
        # Use only name-based matching in Neo4j
        $cypherGlobal = @"
MATCH (u:AZBase {userprincipalname: '$principalName'}), (t:AZTenant {tenantid: '$($TenantId.ToUpper())'})
MERGE (u)-[:AZGlobalAdminEligible]->(t)
"@

        $cypherRole = @"
MATCH (u:AZBase {userprincipalname: '$principalName'}), (r:AZRole {displayname: '$roleName'})
MERGE (u)-[:AZRoleEligible]->(r)
"@
    } else {
        $role   = $roleMap[$roleName]
        $user   = $userMap[$principalName]
        $tenant = $tenantMap.Values | Select-Object -First 1

        if (-not $role) {
            Write-Warning "Role '$roleName' not found in JSON data."
            continue
        }
        if (-not $user) {
            Write-Warning "User '$principalName' not found in JSON data."
            continue
        }
        if (-not $tenant) {
            Write-Warning "No tenant found in JSON data."
            continue
        }

        $cypherGlobal = @"
MATCH (u:AZBase {objectid: '$($user.id.ToUpper())'}), (t:AZTenant {objectid: '$($tenant.tenantId.ToUpper())'})
MERGE (u)-[:AZGlobalAdminEligible]->(t)
"@

        $cypherRole = @"
MATCH (u:AZBase {objectid: '$($user.id.ToUpper())'}), (r:AZRole {objectid: '$($role.id.ToUpper())@$($tenant.tenantId.ToUpper())'})
MERGE (u)-[:AZRoleEligible]->(r)
"@
    }

    # Create Global Administrator edge if applicable
    if ($roleName -eq "Global Administrator") {
        $body = @{ statements = @(@{ statement = $cypherGlobal }) } | ConvertTo-Json -Depth 5
        try {
            $null = Invoke-RestMethod -Uri $Neo4jUrl -Method Post -Headers $headers -Body $body
            Write-Host "Created AZGlobalAdminEligible edge: $principalName -> $roleName"
        } catch {
            Write-Warning "Failed to create GlobalAdmin edge: $_"
        }
    }

    # Create general AZRoleEligible edge
    $body = @{ statements = @(@{ statement = $cypherRole }) } | ConvertTo-Json -Depth 5
    try {
        $null = Invoke-RestMethod -Uri $Neo4jUrl -Method Post -Headers $headers -Body $body
        Write-Host "Created AZRoleEligible edge: $principalName -> $roleName"
    } catch {
        Write-Warning "Failed to create Role edge: $_"
    }
}
