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
If not provided, the script will attempt to retrieve it from Neo4j.

.INPUTS
None. This script does not accept pipeline input.

.OUTPUTS
None. Outputs are written to the console and to the JSON file specified in OutPath.

.EXAMPLE
PS> .\Script.ps1 -CsvPath .\export_example.csv -OutPath .\eligiblehound.json

.EXAMPLE
PS> .\Script.ps1 -CsvPath .\export_example.csv -Neo4jUrl "http://localhost:7474/db/neo4j/tx/commit" -Neo4jUser "neo4j" -Neo4jPassword "bloodhoundcommunityedition"
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
    [string]$TenantId
)

function Test-Neo4jConnection {
    <#
    .SYNOPSIS
    Tests the connection to a Neo4j database using provided credentials.

    .DESCRIPTION
    Attempts to connect to the specified Neo4j transactional Cypher endpoint
    using the given username and password. Returns the headers required for
    subsequent authenticated requests if successful. If the connection fails,
    the function writes a warning and exits the script.

    .PARAMETER Neo4jUrl
    The URL of the Neo4j transactional Cypher endpoint.

    .PARAMETER Neo4jUser
    The username for Neo4j authentication.

    .PARAMETER Neo4jPassword
    The password for Neo4j authentication.

    .OUTPUTS
    [hashtable] - Returns a hashtable containing the HTTP headers for Neo4j requests.

    .EXAMPLE
    $headers = Test-Neo4jConnection -Neo4jUrl "http://localhost:7474/db/neo4j/tx/commit" -Neo4jUser "neo4j" -Neo4jPassword "password"
    #>
    param (
        [string]$Neo4jUrl,
        [string]$Neo4jUser,
        [string]$Neo4jPassword
    )
    $headers = @{
        Authorization = "Basic " + [Convert]::ToBase64String(
            [Text.Encoding]::ASCII.GetBytes("${Neo4jUser}:${Neo4jPassword}")
        )
        "Content-Type" = "application/json"
    }
    $body = '{"statements":[{"statement":"RETURN 1"}]}'
    try {
        Write-Host "Checking Neo4j connection."
        # response variable is not used, but needed so that the result is not returned as an array
        $response = Invoke-RestMethod -Uri $Neo4jUrl -Method Post -Headers $headers -Body $body
        Write-Host "Connection successful: Neo4j credentials are valid."
        return $headers
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
}

function Get-TenantsFromNeo4j {
    <#
    .SYNOPSIS
    Retrieves all tenants from Neo4j and selects the first one.

    .DESCRIPTION
    Queries the Neo4j database for all tenant IDs and names. Lists all tenants in the console output.
    Returns the ID of the first tenant found, which will be used for role assignments.

    .PARAMETER Neo4jUrl
    The URL of the Neo4j transactional Cypher endpoint.

    .PARAMETER Headers
    The HTTP headers for Neo4j requests.

    .OUTPUTS
    [string] - Returns the tenant ID of the first tenant found.

    .EXAMPLE
    $tenantId = Get-TenantsFromNeo4j -Neo4jUrl $Neo4jUrl -Headers $headers
    #>
    param (
        [string]$Neo4jUrl,
        [hashtable]$Headers
    )
    $tenantCypher = "MATCH (t:AZTenant) RETURN t.tenantid AS tenantId, t.displayname AS tenantName"
    $body = @{
        statements = @(@{ statement = $tenantCypher })
    } | ConvertTo-Json -Depth 10

    try {
        Write-Host "Querying Neo4j for tenants..."
        $response = Invoke-RestMethod -Uri $Neo4jUrl -Method Post -Headers $Headers -Body $body
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
        Write-Host "Using tenant '$($tenants[0].Name)' with ID '$($tenants[0].Id)' for role assignments. If this is incorrect, please specify the correct TenantId using the -TenantId parameter."
        return $tenants[0].Id
    } catch {
        Write-Warning "Error querying Neo4j for tenants: $($_.Exception.Message)"
        exit
    }
}

function Get-PrincipalId {
    <#
    .SYNOPSIS
    Retrieves the object ID of a principal from Neo4j.

    .DESCRIPTION
    Queries Neo4j for the object ID of a principal (user/service principal) based on the provided principal name.
    Returns the object ID if found, otherwise returns $null and writes a warning.

    .PARAMETER Neo4jUrl
    The URL of the Neo4j transactional Cypher endpoint.

    .PARAMETER Headers
    The HTTP headers for Neo4j requests.

    .PARAMETER PrincipalName
    The userPrincipalName of the principal to look up.

    .OUTPUTS
    [string] - Returns the object ID of the principal, or $null if not found.

    .EXAMPLE
    $principalId = Get-PrincipalId -Neo4jUrl $Neo4jUrl -Headers $headers -PrincipalName "user@domain.com"
    #>
    param (
        [string]$Neo4jUrl,
        [hashtable]$Headers,
        [string]$PrincipalName
    )
    $principalCypher = "MATCH (u:AZBase {userprincipalname: '$PrincipalName'}) RETURN u.objectid AS principalId"
    $body = @{
        statements = @(@{ statement = $principalCypher })
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri $Neo4jUrl -Method Post -Headers $Headers -Body $body
        if ($response.results[0].data.Count -gt 0) {
            return $response.results[0].data[0].row[0]
        } else {
            Write-Warning "Principal '$PrincipalName' not found in Neo4j. Skipping assignment."
            return $null
        }
    } catch {
        Write-Warning "Error querying Neo4j for principal '$PrincipalName': $($_.Exception.Message)"
        return $null
    }
}

function Get-RoleId {
    <#
    .SYNOPSIS
    Retrieves the object ID of a role from Neo4j.

    .DESCRIPTION
    Queries Neo4j for the object ID of a role based on the provided role name.
    Returns the object ID if found, otherwise returns $null and writes a warning.

    .PARAMETER Neo4jUrl
    The URL of the Neo4j transactional Cypher endpoint.

    .PARAMETER Headers
    The HTTP headers for Neo4j requests.

    .PARAMETER RoleName
    The display name of the role to look up.

    .OUTPUTS
    [string] - Returns the object ID of the role, or $null if not found.

    .EXAMPLE
    $roleId = Get-RoleId -Neo4jUrl $Neo4jUrl -Headers $headers -RoleName "Global Administrator"
    #>
    param (
        [string]$Neo4jUrl,
        [hashtable]$Headers,
        [string]$RoleName
    )
    $roleCypher = "MATCH (r:AZRole {displayname: '$RoleName'}) RETURN r.objectid AS roleId"
    $body = @{
        statements = @(@{ statement = $roleCypher })
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod -Uri $Neo4jUrl -Method Post -Headers $Headers -Body $body
        if ($response.results[0].data.Count -gt 0) {
            $roleId = $response.results[0].data[0].row[0]
            # Extract only the part before '@' from roleId
            if ($roleId -match "^([^@]+)@") {
                $roleId = $matches[1]
            }
            return $roleId
        } else {
            Write-Warning "Role '$RoleName' not found in Neo4j. Skipping assignment."
            return $null
        }
    } catch {
        Write-Warning "Error querying Neo4j for role '$RoleName': $($_.Exception.Message)"
        return $null
    }
}

function New-RoleAssignment {
    <#
    .SYNOPSIS
    Constructs a role assignment object for BloodHound.

    .DESCRIPTION
    Builds a hashtable representing a role assignment, including role and principal IDs,
    and other required fields for BloodHound ingestion.

    .PARAMETER RoleId
    The object ID of the role definition.

    .PARAMETER PrincipalId
    The object ID of the principal.

    .OUTPUTS
    [hashtable] - Returns a hashtable representing the role assignment.

    .EXAMPLE
    $roleAssignment = New-RoleAssignment -RoleId $roleId -PrincipalId $principalId
    #>
    param (
        [string]$RoleId,
        [string]$PrincipalId
    )
    return @{
        id                = ""
        roleDefinitionId  = $RoleId
        principalId       = $PrincipalId
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
}

function Write-JsonOutput {
    <#
    .SYNOPSIS
    Writes the role assignment data to a JSON file.

    .DESCRIPTION
    Converts the provided data array to JSON and writes it to the specified output path.
    Also writes meta information required by BloodHound.

    .PARAMETER DataArray
    The array of role assignment objects to write.

    .PARAMETER OutPath
    The path to the output JSON file.

    .OUTPUTS
    None. Writes output to a file.

    .EXAMPLE
    Write-JsonOutput -DataArray $dataArray -OutPath "eligiblehound.json"
    #>
    param (
        [array]$DataArray,
        [string]$OutPath
    )
    $updateJson = @{
        data = $DataArray
        meta = @{
            type    = "azure"
            version = 5
            count   = $DataArray.Count
        }
    }
    Write-Host "Starting to write JSON to $OutPath"
    $updateJson | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $OutPath -Encoding UTF8
    Write-Host "Writing JSON completed"
    Write-Host "You can now import the file $OutPath into BloodHound."
}

# Main script logic

Write-Host "Starting to read CSV $CsvPath"
$csv = Import-Csv -Path $CsvPath -Delimiter ";"
Write-Host "Reading CSV completed"

$headers = Test-Neo4jConnection -Neo4jUrl $Neo4jUrl -Neo4jUser $Neo4jUser -Neo4jPassword $Neo4jPassword

if (-not $TenantId) {
    $TenantId = Get-TenantsFromNeo4j -Neo4jUrl $Neo4jUrl -Headers $headers
}

$dataArray = @()

foreach ($entry in $csv) {
    $roleName      = $entry.'Role Name'
    $principalName = $entry.PrincipalName

    $principalId = Get-PrincipalId -Neo4jUrl $Neo4jUrl -Headers $headers -PrincipalName $principalName
    if (-not $principalId) { continue }

    $roleId = Get-RoleId -Neo4jUrl $Neo4jUrl -Headers $headers -RoleName $roleName
    if (-not $roleId) { continue }

    $roleAssignment = New-RoleAssignment -RoleId $roleId -PrincipalId $principalId

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

Write-JsonOutput -DataArray $dataArray -OutPath $OutPath