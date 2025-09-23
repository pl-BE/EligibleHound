<#
.SYNOPSIS
Getting eligible role assignments from EntraID/Azure into BloodHound.

.DESCRIPTION
This script reads a CSV file containing role assignments and generates 
a JSON file compatible with BloodHound. It connects to a Neo4j database 
to retrieve necessary information about roles and principals.

.PARAMETER CsvPath
Specifies the path to the role assignment CSV file.
Default: export_example.csv

.PARAMETER OutPath
Specifies the path where the created JSON file will be saved.
Default: eligiblehound.json

.PARAMETER Neo4jUrl
The URL of the Neo4j transactional Cypher endpoint.
Default: http://localhost:7474/db/neo4j/tx/commit

.PARAMETER Neo4jUser
The username for Neo4j authentication.
Default: neo4j

.PARAMETER Neo4jPassword
The password for Neo4j authentication.
Default: bloodhoundcommunityedition

.PARAMETER TenantId
Specifies the Azure tenant ID.

.INPUTS
None. This script does not accept pipeline input.

.OUTPUTS
None. Outputs are written to the console and to the JSON file specified in OutPath.

.EXAMPLE
PS> .\Script.ps1 -CsvPath .\export_example.csv -TenantId "6c12b0b0-b2cc-4a73-8252-0b94bfca2145"

.EXAMPLE
PS> Get-Help .\Script.ps1 -Detailed

#>

param (
    [string]$CsvPath = "export_example.csv",
    [string]$OutPath = "eligiblehound.json",
    [string]$Neo4jUrl = "http://localhost:7474/db/neo4j/tx/commit",
    [string]$Neo4jUser = "neo4j",
    [string]$Neo4jPassword = "bloodhoundcommunityedition",
    [switch]$LowMemoryMode,
    [string]$TenantId
)

# CSV einlesen
Write-Host "Starting to read CSV $CsvPath"
$csv = Import-Csv -Path $CsvPath -Delimiter ";"
Write-Host "Reading CSV completed"

# Check Neo4j Connection
$headers = @{
    Authorization = "Basic " + [Convert]::ToBase64String(
        [Text.Encoding]::ASCII.GetBytes("${neo4jUser}:${neo4jPassword}")
    )
    "Content-Type" = "application/json"
}
$body = '{"statements":[{"statement":"RETURN 1"}]}'
try {
    Write-Host "Checking Neo4j connection."
    $response = Invoke-RestMethod -Uri $neo4jUrl -Method Post -Headers $headers -Body $body
    Write-Host "Connection successful: Neo4j credentials are valid."
} catch {
    $statusCode = $null
    $statusDesc = $null
    if ($_.Exception.Response){
        $statusCode = $_.Exception.Response.StatusCode.Value__
        $statusDesc = $_.Exception.Response.StatusDescription
        if ($statusCode -eq 401 -and $statusDesc -eq "Unauthorized"){
            Write-Warning "Neo4j Unauthorized. Check your username and password."
        }
    }
    else {
        Write-Warning "Neo4j connection failed. $($_.Exception.Message)"
    }
    exit
}

# Datenstruktur für BloodHound
$dataArray = @()

# Prepare Neo4j API request headers
$headers = @{
    Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${Neo4jUser}:${Neo4jPassword}"))
    "Content-Type" = "application/json"
}

    # Get all tenant IDs and names from Neo4j
    $tenantCypher = "MATCH (t:AZTenant) RETURN t.tenantid AS tenantId, t.displayname AS tenantName"
    $body = @{
        statements = @(@{ statement = $tenantCypher })
    } | ConvertTo-Json -Depth 10

    try {
        Write-Host "Querying Neo4j for tenants..."
        $response = Invoke-RestMethod -Uri $Neo4jUrl -Method Post -Headers $headers -Body $body
        $tenants = @()
        foreach ($row in $response.results[0].data) {
            $tenantId = $row.row[0]
            $tenantName = $row.row[1]
            $tenants += [PSCustomObject]@{ Id = $tenantId; Name = $tenantName }
        }

        if ($tenants.Count -eq 0) {
            Write-Warning "No tenants found in Neo4j. Please check your database or use the -TenantId parameter."
            exit
        }

        Write-Host "Available tenants in Neo4j:"
        $i = 1
        foreach ($tenant in $tenants) {
            Write-Host "$i. Name: $($tenant.Name) | ID: $($tenant.Id)"
            $i++
        }

        # Choose the first tenant
        $TenantId = $tenants[0].Id
        Write-Host "Using tenant '$($tenants[0].Name)' with ID '$TenantId' for role assignments. If this is incorrect, please specify the correct TenantId using the -TenantId parameter."
    } catch {
        Write-Warning "Error querying Neo4j for tenants: $($_.Exception.Message)"
        exit
    }

foreach ($entry in $csv) {
    $roleName      = $entry.'Role Name'
    $principalName = $entry.PrincipalName

    $principalCypher = "MATCH (u:AZBase {userprincipalname: '$principalName'}) RETURN u.objectid AS principalId"
    $roleCypher = "MATCH (r:AZRole {displayname: '$roleName'}) RETURN r.objectid AS roleId"

    # Get principalId from Neo4j
    try {
        $body = @{
            statements = @(@{ statement = $principalCypher })
        } | ConvertTo-Json -Depth 10

        $response = Invoke-RestMethod -Uri $Neo4jUrl -Method Post -Headers $headers -Body $body
        if ($response.results[0].data.Count -gt 0) {
            $principalId = $response.results[0].data[0].row[0]
        } else {
            Write-Warning "Principal '$principalName' not found in Neo4j. Skipping assignment."
            continue
        }
    } catch {
        Write-Warning "Error querying Neo4j for principal '$principalName': $($_.Exception.Message)"
        continue
    }
    # Get roleId from Neo4j
    try {
        $body = @{
            statements = @(@{ statement = $roleCypher })
        } | ConvertTo-Json -Depth 10

        $response = Invoke-RestMethod -Uri $Neo4jUrl -Method Post -Headers $headers -Body $body
        if ($response.results[0].data.Count -gt 0) {
            $roleId = $response.results[0].data[0].row[0]
        } else {
            Write-Warning "Role '$roleName' not found in Neo4j. Skipping assignment."
            continue
        }
    } catch {
        Write-Warning "Error querying Neo4j for role '$roleName': $($_.Exception.Message)"
        continue
    }
    # Extract only the part before '@' from roleId
    if ($roleId -match "^([^@]+)@") {
        $roleId = $matches[1]
    }

    $roleAssignment = @{
        id                = ""
        roleDefinitionId  = $roleId
        principalId       = $principalId
        directoryScopeId  = "/"
        roleDefinition    = @{
            id              = ""
            description     = ""
            displayName     = ""
            isBuiltIn       = $false
            isEnabled       = $false
            rolePermisions  = $null
            version         = ""
        }
        DirectoryScope    = $null
        appScope          = @{
            id            = ""
            display_name  = ""
            type          = ""
        }
    }

    $azRoleAssignment = @{
        kind = "AZRoleAssignment"
        data = @{
            roleAssignments   = @($roleAssignment)
            roleDefinitionId  = $roleId
            tenantId          = $TenantId
        }
    }

    $dataArray += $azRoleAssignment

    Write-Host "Assignment added: $roleName : $principalName"
}

# meta-Tag erstellen
$updateJson = @{
    data = $dataArray
    meta = @{
        type    = "azure"
        version = 5
        count   = $dataArray.Count
    }
}

# JSON aktualisieren und speichern
Write-Host "Starting to write JSON to $OutPath"
$updateJson | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $OutPath -Encoding UTF8
Write-Host "Writing JSON completed"
Write-Host "You can now import the file $OutPath into BloodHound."