# F3 | owner group: F3 (database tooling) | purpose: rebuild railway_db from every db\*.sql file, then run the contract verifier
#
# Usage:   .\scripts\init-db.ps1            (schema, functions, procedures, triggers, views, seeds)
#          .\scripts\init-db.ps1 -Demo      (same, plus db\60_demo_data.sql)
#
# Environment variables (all optional):
#   MYSQL_USER (default root)   MYSQL_HOST (default 127.0.0.1)
#   MYSQL_PORT (default 3306)   MYSQL_PWD  (if not set, the script asks for it)
param(
    [switch]$Demo
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$DbDir     = Join-Path $RepoRoot 'db'
$Verifier  = Join-Path $ScriptDir 'verify-contract.sql'

# ---- 1. connection settings --------------------------------------------------
$MysqlUser = if ($env:MYSQL_USER) { $env:MYSQL_USER } else { 'root' }
$MysqlHost = if ($env:MYSQL_HOST) { $env:MYSQL_HOST } else { '127.0.0.1' }
$MysqlPort = if ($env:MYSQL_PORT) { $env:MYSQL_PORT } else { '3306' }

if (-not (Get-Command mysql -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: the 'mysql' command line client was not found on PATH." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $DbDir)) {
    Write-Host "ERROR: folder not found: $DbDir" -ForegroundColor Red
    exit 1
}

if (-not $env:MYSQL_PWD) {
    $secure = Read-Host -Prompt "MySQL password for user '$MysqlUser' (press Enter for none)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $env:MYSQL_PWD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

# ---- helpers -----------------------------------------------------------------

# Runs the mysql client once. If $InputFile is given its bytes are sent to mysql's standard input
# (this is how a .sql file is executed; PowerShell has no "<" operator).
# Returns an object with ExitCode, Output and Error.
function Invoke-MySql {
    param(
        [string[]]$ExtraArgs = @(),
        [string]$InputFile = ''
    )

    $allArgs = @("--host=$MysqlHost", "--port=$MysqlPort", "--user=$MysqlUser",
                 '--default-character-set=utf8mb4') + $ExtraArgs
    # Quote every argument that contains a space or a double quote.
    $argLine = ($allArgs | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'mysql'
    $psi.Arguments              = $argLine
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [Text.Encoding]::UTF8

    $proc    = [System.Diagnostics.Process]::Start($psi)
    $outTask = $proc.StandardOutput.ReadToEndAsync()   # read asynchronously to avoid pipe deadlock
    $errTask = $proc.StandardError.ReadToEndAsync()

    try {
        if ($InputFile -ne '') {
            $bytes  = [IO.File]::ReadAllBytes($InputFile)
            $offset = 0
            # Skip a UTF-8 byte-order mark if present (mysql rejects a BOM).
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $offset = 3
            }
            $proc.StandardInput.BaseStream.Write($bytes, $offset, $bytes.Length - $offset)
        }
    } catch {
        # mysql may exit early on an error and close the pipe; its error text is read below.
    } finally {
        try { $proc.StandardInput.Close() } catch { }
    }

    $proc.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        Output   = $outTask.Result
        Error    = $errTask.Result
    }
}

# Runs one SQL file. Stops the whole script with the file name and the mysql error on failure.
function Invoke-SqlFile {
    param(
        [string]$Path,
        [string[]]$ExtraArgs = @()
    )
    $result = Invoke-MySql -ExtraArgs $ExtraArgs -InputFile $Path
    if ($result.ExitCode -ne 0) {
        Write-Host ""
        Write-Host "FAILED FILE: $Path" -ForegroundColor Red
        Write-Host "MYSQL ERROR: $($result.Error)$($result.Output)" -ForegroundColor Red
        exit 1
    }
    if ($result.Output.Trim() -ne '') { Write-Host $result.Output.TrimEnd() }
    if ($result.Error.Trim()  -ne '') { Write-Host $result.Error.TrimEnd() }
}

# ---- 2. allow stored functions with binary logging on ------------------------
$trust = Invoke-MySql -ExtraArgs @('--execute=SET GLOBAL log_bin_trust_function_creators = 1;')
if ($trust.ExitCode -ne 0) {
    Write-Warning "Could not run SET GLOBAL log_bin_trust_function_creators = 1 (needs SUPER privilege)."
    Write-Warning "Details: $($trust.Error.Trim())"
    Write-Warning "Continuing; creating functions may fail if binary logging is enabled."
}

# ---- 3. create the empty database (db\00_database.sql, no --database option) -
$dbFile = Join-Path $DbDir '00_database.sql'
if (-not (Test-Path -LiteralPath $dbFile)) {
    Write-Host "ERROR: $dbFile not found." -ForegroundColor Red
    exit 1
}
Write-Host ">>> Running 00_database.sql"
Invoke-SqlFile -Path $dbFile

# ---- 4. collect all numbered files (sorted by name), skip 00 and maybe 60 ----
# Only files directly inside db\ are considered, so db\tests\ is excluded automatically.
$names = @(Get-ChildItem -LiteralPath $DbDir -File |
    Where-Object { $_.Name -match '^[0-9][0-9]_.*\.sql$' } |
    ForEach-Object { $_.Name })
[Array]::Sort($names, [StringComparer]::Ordinal)   # plain byte order: 01_, 10_, 20_ ...

# ---- 5. run them in order, stop at the first error ---------------------------
foreach ($name in $names) {
    if ($name -eq '00_database.sql') { continue }   # already executed above
    if ($name -eq '60_demo_data.sql' -and -not $Demo) {
        Write-Host "--- Skipping 60_demo_data.sql (use -Demo to include it)"
        continue
    }
    Write-Host ">>> Running $name"
    Invoke-SqlFile -Path (Join-Path $DbDir $name) -ExtraArgs @('--database=railway_db')
}

Write-Host ""
Write-Host "DB READY"
Write-Host ""

# ---- 6. contract verifier ----------------------------------------------------
if (-not (Test-Path -LiteralPath $Verifier)) {
    Write-Host "ERROR: $Verifier not found." -ForegroundColor Red
    exit 1
}
Write-Host ">>> Running verify-contract.sql"
Invoke-SqlFile -Path $Verifier -ExtraArgs @('--database=railway_db', '--table')
exit 0
