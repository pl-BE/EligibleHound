# EligibleHound PowerShell Script

## 📝 Description

This PowerShell script reads a CSV file containing role assignments and generates a JSON file in the BloodHound-compatible format.  
It connects to a Neo4j database to retrieve the required IDs and names for roles, users, and tenants.  
The new role assignments are written as objects into the JSON structure and can then be imported into BloodHound.

## 📂 Input Files

- **CSV file (`export_example.csv`)**  
  Contains role assignments with the following relevant columns:
  - `Role Name` or `roleDisplayName`
  - `User Group Name` or `User/Group Name` (display name of the user or group)
  - `User Group Name`, `User/Group Name` or `displayName`
  - (Other columns are ignored)
  This file can for example be a export from Entra or Azure.

- **Neo4j Database**  
  The IDs and names for roles, users, and tenants are queried directly from Neo4j.

## 📤 Output File

- **`eligiblehound.json`**  
  A new JSON file with the generated role assignments in BloodHound format.

## ⚙️ How It Works

1. **Read CSV**  
   The CSV is read and processed row by row.

2. **Connect to Neo4j**  
   The provided credentials are used to test the connection to Neo4j.

3. **Determine Tenant**  
   All tenants are queried from Neo4j and displayed in the terminal. The first tenant found is automatically used for the role assignments.

4. **Resolve IDs for Users and Roles**  
   For each row, the required IDs are queried from Neo4j.  
   The user/group is identified by the display name (`User Group Name` or `User/Group Name`).

5. **Create Role Assignments**  
   For each valid combination, a new role assignment object is created.

6. **Write JSON**  
   The generated objects are written to the output file.

## ▶️ Usage

```powershell
# Example call with default values
.\EligibleHound.ps1

# With custom parameters
.\EligibleHound.ps1 -CsvPath .\export_example.csv -OutPath .\eligiblehound.json -Neo4jUrl "http://localhost:7474/db/neo4j/tx/commit" -Neo4jUser "neo4j" -Neo4jPassword "bloodhoundcommunityedition"
```

## ⚠️ Notes

- The Neo4j credentials are passed as parameters.
- Tenant selection is automatic based on the first tenant found in Neo4j (displayed in the terminal).
- The principal (user, group, or service principal) is identified as follows:
  - If the `PrincipalName` field contains an `@`, it is treated as a user and resolved by UPN.
  - If the `PrincipalName` field is set but does not contain an `@`, it is treated as a service principal and resolved by display name (contains).
  - If the `PrincipalName` field is not set, it is treated as a group and resolved by display name (contains).
  - For display name lookups, the script checks the columns `User Group Name`, `User/Group Name`, or `displayName`.
- The role is identified by the role display name (`Role Name` or `roleDisplayName`).
- The CSV delimiter can be either a semicolon (`;`) or a comma (`,`); the script auto-detects the delimiter.

## 📌 Example Output

```
Starting to read CSV export_example.csv
Reading CSV completed
Checking Neo4j connection.
Connection successful: Neo4j credentials are valid.
Querying Neo4j for tenants...
Available tenants in Neo4j:
1. Name: ExampleTenant | ID: 12345678-1234-1234-1234-123456789abc
Using tenant 'ExampleTenant' with ID '12345678-1234-1234-1234-123456789abc' for role assignments. If this is incorrect, please specify the correct TenantId using the -TenantId parameter.
Assignment added: Contributor : Max Mustermann
Writing JSON completed
You can now import the file eligiblehound.json into BloodHound.
```