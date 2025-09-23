# EligibleHound PowerShell Script

## 📝 Beschreibung

Dieses PowerShell-Skript liest eine CSV-Datei mit Rollenzuweisungen und generiert eine JSON-Datei im BloodHound-kompatiblen Format.  
Es verbindet sich mit einer Neo4j-Datenbank, um die benötigten IDs und Namen für Rollen, Benutzer und Tenant zu ermitteln.  
Die neuen Rollenzuweisungen werden als Objekte in die JSON-Struktur geschrieben und können anschließend in BloodHound importiert werden.

## 📂 Eingabedateien

- **CSV-Datei (`export_example.csv`)**  
  Enthält Rollenzuweisungen mit folgenden relevanten Spalten:
  - `Role Name`
  - `PrincipalName`
  - (Weitere Spalten werden ignoriert)

- **Neo4j-Datenbank**  
  Die IDs und Namen für Rollen, Benutzer und Tenant werden direkt aus Neo4j abgefragt.

## 📤 Ausgabedatei

- **`eligiblehound.json`**  
  Eine neue JSON-Datei mit den generierten Rollenzuweisungen im BloodHound-Format.

## ⚙️ Funktionsweise

1. **CSV einlesen**  
   Die CSV wird eingelesen und Zeile für Zeile verarbeitet.

2. **Verbindung zu Neo4j herstellen**  
   Die Zugangsdaten werden verwendet, um die Verbindung zu Neo4j zu testen.

3. **Tenant ermitteln**  
   Alle Tenants werden aus Neo4j abgefragt und im Terminal angezeigt. Der erste Tenant wird automatisch für die Rollenzuweisungen verwendet.

4. **IDs für Benutzer und Rollen auflösen**  
   Für jede Zeile werden die benötigten IDs aus Neo4j abgefragt.

5. **Rollenzuweisungen erzeugen**  
   Für jede gültige Kombination wird ein neues Rollenzuweisungsobjekt erstellt.

6. **JSON schreiben**  
   Die generierten Objekte werden in die Ausgabedatei geschrieben.

## ▶️ Nutzung

```powershell
# Beispielaufruf mit Standardwerten
.\EligibleHound.ps1

# Mit eigenen Parametern
.\EligibleHound.ps1 -CsvPath .\export_example.csv -OutPath .\eligiblehound.json -Neo4jUrl "http://localhost:7474/db/neo4j/tx/commit" -Neo4jUser "neo4j" -Neo4jPassword "bloodhoundcommunityedition"
```

## ⚠️ Hinweise

- Die CSV-Datei muss das Semikolon (`;`) als Trennzeichen verwenden.
- Die Neo4j-Zugangsdaten werden als Parameter übergeben.
- Die Tenant-Auswahl erfolgt automatisch anhand des ersten gefundenen Tenants in Neo4j (wird im Terminal angezeigt).

## 📌 Beispielausgabe

```
Starting to read CSV export_example.csv
Reading CSV completed
Checking Neo4j connection.
Connection successful: Neo4j credentials are valid.
Querying Neo4j for tenants...
Available tenants in Neo4j:
1. Name: ExampleTenant | ID: 12345678-1234-1234-1234-123456789abc
Using tenant 'ExampleTenant' with ID '12345678-1234-1234-1234-123456789abc' for role assignments. If this is incorrect, please specify the correct TenantId using the -TenantId parameter.
Assignment added: Contributor : user@example.com
Writing JSON completed
You can now import the file eligiblehound.json into BloodHound.
```