# Konfiguration
$csvPath = "export_example.csv"
$jsonPath = "azurehound_example.json"
$neo4jUrl = "http://localhost:7474/db/neo4j/tx/commit"
$neo4jUser = "neo4j"
$neo4jPassword = "bloodhoundcommunityedition"

# JSON lesen
Write-Host "Lese JSON $jsonPath"
$json = Get-Content $jsonPath -Raw | ConvertFrom-Json

# Rollen- und Benutzerzuordnung vorbereiten
$roleMap = @{}
$userMap = @{}
$tenantMap = @{}

foreach ($entry in $json.data) {
    switch ($entry.kind) {
        "AZRole" {
            $roleMap[$entry.data.displayName] = $entry.data
        }
        "AZUser" {
            $userMap[$entry.data.userPrincipalName] = $entry.data
        }
        "AZTenant" {
            $tenantMap[$entry.data.tenantId] = $entry.data
        }
    }
}

# CSV lesen und filtern
Write-Host "Lese CSV $csvPath"
$csv = Import-Csv -Path $csvPath -Delimiter ";" | Where-Object { $_."Assignment State" -eq "Eligible" }

# Für jede Eligible-Zeile eine Beziehung in Neo4j anlegen
foreach ($entry in $csv) {
    $roleName = $entry."Role Name"
    $principalName = $entry.PrincipalName

    $role = $roleMap[$roleName]
    $user = $userMap[$principalName]
    $tenant = $tenantMap.Values | Select-Object -First 1

    if (-not $role) {
        Write-Warning "Role '$roleName' not found."
        continue
    }

    if (-not $user) {
        Write-Warning "User '$principalName' not found."
        continue
    }

    if (-not $tenant) {
        Write-Warning "No tenant found."
        continue
    }

    if ($role.displayName -eq "Global Administrator"){
        $cypherAZGlobalAdminEligible = @"
MATCH (u:AZBase {objectid: '$($user.id.ToUpper())'}), (r:AZTenant {objectid: '$($tenant.tenantId.ToUpper())'})
MERGE (u)-[:AZGlobalAdminEligible]->(r)
"@
        
        $body = @{
            statements = @(@{
                statement = $cypherAZGlobalAdminEligible
            })
        } | ConvertTo-Json -Depth 5

        $headers = @{
            Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${neo4jUser}:${neo4jPassword}"))
            "Content-Type" = "application/json"
        }

        try {
            $response = Invoke-RestMethod -Uri $neo4jUrl -Method Post -Headers $headers -Body $body
            Write-Host "Beziehung AZGolbalAdminEligible erstellt: $principalName -> $roleName"
        } catch {
            Write-Warning "Fehler beim Erstellen der Beziehung: $_"
        }
    }
    
    $cypherAZRoleEligible = @"
MATCH (u:AZBase {objectid: '$($user.id.ToUpper())'}), (r:AZRole {objectid: '$($role.id.ToUpper())@$($tenant.tenantId.ToUpper())'})
MERGE (u)-[:AZRoleEligible]->(r)
"@

    $body = @{
        statements = @(@{
            statement = $cypherAZRoleEligible
        })
    } | ConvertTo-Json -Depth 5

    $headers = @{
        Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${neo4jUser}:${neo4jPassword}"))
        "Content-Type" = "application/json"
    }

    try {
        $response = Invoke-RestMethod -Uri $neo4jUrl -Method Post -Headers $headers -Body $body
        Write-Host "Beziehung AZRoleEligible erstellt: $principalName -> $roleName"
    } catch {
        Write-Warning "Fehler beim Erstellen der Beziehung: $_"
    }
}
