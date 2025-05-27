# CSV and JSON files
$csvPath = "export_example.csv"
$jsonPath = "azurehound_example.json"
$outputPath = "eligiblehound.json"

# Read JSON
Write-Host "Starting to read JSON $jsonPath"
$json = Get-Content $jsonPath -Raw | ConvertFrom-Json
Write-Host "Reading JSON completed"

# Prepare role and user assignments
$roleMap = @{}
$userMap = @{}

foreach ($entry in $json.data) {
    switch ($entry.kind) {
        "AZRole" {
            $roleMap[$entry.data.displayName] = $entry.data.id
        }
        "AZUser" {
            $userMap[$entry.data.userPrincipalName] = $entry.data.id
        }
    }
}

# Read and filter CSV
Write-Host "Starting to read CSV $csvPath"
$csv = Import-Csv -Path $csvPath -Delimiter ";" | Where-Object { $_."Assignment State" -eq "Eligible" }
Write-Host "Reading CSV completed"

# Create JSON containing eligible role assignments
$updateJson = @{
    data = @()
    meta = $json.meta
}

foreach ($entry in $csv) {
    $roleName = $entry."Role Name"
    $principalName = $entry.PrincipalName

    # Resolve role
    $roleId = $roleMap[$roleName]
    if (-not $roleId) {
        Write-Warning "Rolle '$roleName' nicht gefunden."
        continue
    }

    # Resolve user
    $principalId = $userMap[$principalName]
    if (-not $principalId) {
        Write-Warning "Benutzer '$principalName' nicht gefunden."
        continue
    }

    # Find role assignment entry in JSON file
    $roleAssignmentEntry = $json.data | Where-Object { $_.kind -eq "AZRoleAssignment" -and $_.data.roleDefinitionId -eq $roleId }
    if (-not $roleAssignmentEntry) {
        Write-Warning "Kein AZRoleAssignment-Eintrag für Rolle '$roleName' gefunden."
        continue
    }

    # Create new role assignment
    $newAssignment = @{
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

    # Add new assignment to existing assignments
    $roleAssignmentEntry.data.roleAssignments += $newAssignment
    $updateJson.data += $roleAssignmentEntry

    Write-Host "Assignment added by EligibleHound: $roleName : $principalName"
}

# Format and save JSON
Write-Host "Starting to write JSON to $outputPath"
$updateJson = $updateJson | ConvertTo-Json -Depth 10 -Compress
$updateJson | Set-Content -Path $outputPath -Encoding UTF8
Write-Host "Writing JSON completed"