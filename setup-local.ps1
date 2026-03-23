param(
    [ValidateSet("build", "test", "run", "verify", "package-exe", "all")]
    [string]$Action = "build"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$mavenRepoDir = Join-Path $repoRoot "build\.m2\repository"
$launcherScript = Join-Path $repoRoot "launcher\build-windows-exe.ps1"

function Resolve-MavenCommand {
    $command = Get-Command mvn.cmd -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    if ($env:MAVEN_HOME) {
        $fromMavenHome = Join-Path $env:MAVEN_HOME "bin\mvn.cmd"
        if (Test-Path $fromMavenHome) {
            return $fromMavenHome
        }
    }

    $knownPaths = @(
        "C:\Tools\apache-maven-3.9.14\bin\mvn.cmd",
        "C:\apache-maven-3.9.14\bin\mvn.cmd"
    )

    foreach ($path in $knownPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    throw "Could not find mvn.cmd. Install Maven or add it to PATH/MAVEN_HOME."
}

$mavenCommand = Resolve-MavenCommand

function Ensure-MavenRepo {
    if (-not (Test-Path $mavenRepoDir)) {
        New-Item -ItemType Directory -Path $mavenRepoDir -Force | Out-Null
    }
}

function Invoke-Maven {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Ensure-MavenRepo
    Push-Location $repoRoot
    try {
        & $mavenCommand "-Dmaven.repo.local=$mavenRepoDir" @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Maven failed with exit code $LASTEXITCODE."
        }
    }
    finally {
        Pop-Location
    }
}

function Get-BuiltJar {
    $targetDir = Join-Path $repoRoot "target"
    if (-not (Test-Path $targetDir)) {
        return $null
    }

    return Get-ChildItem (Join-Path $targetDir "SESEditor-*.jar") |
        Where-Object { $_.Name -notlike "original-*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Ensure-BuiltJar {
    $jar = Get-BuiltJar
    if ($null -eq $jar) {
        Invoke-Maven -Arguments @("clean", "package", "-DskipTests")
        $jar = Get-BuiltJar
    }

    if ($null -eq $jar) {
        throw "No packaged jar found under target\SESEditor-*.jar"
    }

    return $jar
}

switch ($Action) {
    "build" {
        Invoke-Maven -Arguments @("clean", "package", "-DskipTests")
    }
    "test" {
        Invoke-Maven -Arguments @("test")
    }
    "verify" {
        Invoke-Maven -Arguments @("verify")
    }
    "run" {
        $jar = Ensure-BuiltJar
        Push-Location $repoRoot
        try {
            & java -jar $jar.FullName
            if ($LASTEXITCODE -ne 0) {
                throw "java -jar failed with exit code $LASTEXITCODE."
            }
        }
        finally {
            Pop-Location
        }
    }
    "package-exe" {
        if (-not (Test-Path $launcherScript)) {
            throw "Windows launcher script not found: $launcherScript"
        }
        Push-Location $repoRoot
        try {
            & powershell -ExecutionPolicy Bypass -File $launcherScript
            if ($LASTEXITCODE -ne 0) {
                throw "Windows packaging failed with exit code $LASTEXITCODE."
            }
        }
        finally {
            Pop-Location
        }
    }
    "all" {
        Invoke-Maven -Arguments @("clean", "test", "package")
    }
}
