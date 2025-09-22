<#
.SYNOPSIS
Getting eligible role assignments from EntraID/Azure into BloodHound.

.DESCRIPTION

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

# Datenstruktur für BloodHound
$dataArray = @()

foreach ($entry in $csv) {
    $roleName      = $entry.RoleName
    $principalName = $entry.PrincipalName
    $roleId        = $entry.RoleObjectId
    $principalId   = $entry.PrincipalObjectId

    $roleAssignment = @{
        id                = "Added by EligibleHound: $roleName : $principalName"
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

    Write-Host "Assignment added by EligibleHound: $roleName : $principalName"
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