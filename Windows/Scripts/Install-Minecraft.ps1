# Install-Minecraft.ps1
# Author: Dylan Harvey
# Downloads and installs a Minecraft server, specify version as a parameter, or assume latest. Also has option to start after installation.
param (
    [string]$MinecraftVersion,
    [switch]$Start
)

[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
$global:ProgressPreference = "SilentlyContinue"

# === Constant Vars ===
$InstallDir = "C:\Oracle\MinecraftServer"

$JavaDownloads = @{
    # 5  = ""  # Idk if i can find this
    # 6  = ""  # RARE
    8  = "https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u442-b06/OpenJDK8U-jdk_x64_windows_hotspot_8u442b06.zip"
    16 = "https://github.com/adoptium/temurin16-binaries/releases/download/jdk-16.0.2%2B7/OpenJDK16U-jdk_x64_windows_hotspot_16.0.2_7.zip"
    17 = "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.9%2B9.1/OpenJDK17U-jdk_x64_windows_hotspot_17.0.9_9.zip"
    21 = "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.6%2B7/OpenJDK21U-jdk_x64_windows_hotspot_21.0.6_7.zip"
}

$serverProperties = @{
    "allow-flight"               = "true"
    "difficulty"                 = "hard"
    "enable-command-block"       = "true"
    "enforce-secure-profile"     = "false"
    "motd"                       = "Yes."
    "online-mode"                = "false"
    "simulation-distance"        = "10"
    "spawn-protection"           = "3"
    "sync-chunk-writes"          = "false"
    "view-distance"              = "10"
}

# Function Definitions
function Get-JavaVersion([version]$ver) {
    # if ($ver -lt [version]"1.6.1")    { return 5 }
    # elseif ($ver -lt [version]"1.12") { return 6 }
    if ($ver -lt [version]"1.17") { return 8 }
    elseif ($ver -lt [version]"1.18") { return 16 }
    elseif ($ver -lt [version]"1.21.5") { return 17 }
    else { return 21 }
}

function Install-JavaLocally {
    param (
        [int]$JavaVersion,
        [string]$TargetDir
    )

    $jdkUrl = $JavaDownloads[$JavaVersion]
    if (-not $jdkUrl) { throw "No download URL for Java $JavaVersion" }

    if (-not (Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }
    $zipFile = "$TargetDir\jdk.zip"

    Write-Host "Downloading Java $JavaVersion..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $jdkUrl -OutFile $zipFile

    Write-Host "Extracting JDK..." -ForegroundColor Magenta
    Expand-Archive -Path $zipFile -DestinationPath $TargetDir -Force

    $javaExe = Get-ChildItem -Path $TargetDir -Recurse -Filter "java.exe" | Select-Object -First 1
    if (-not $javaExe) { throw "Java failed to install correctly."}
    if ($javaExe) { Write-Host "Java installed successfully." -ForegroundColor Green}
    return $javaExe.FullName
}

function Get-ServerJarUrl {
    param ([string]$Version)

    Write-Host "Resolving download URL for Minecraft $Version..." -ForegroundColor Cyan
    $manifest = Invoke-RestMethod -Uri "https://launchermeta.mojang.com/mc/game/version_manifest.json"

    if (-not $Version) {
        $Version = $manifest.latest.release
        Write-Host "No version provided, default to latest: $Version" -ForegroundColor Yellow
    }

    $entry = $manifest.versions | Where-Object { $_.id -eq $Version }
    if (-not $entry) { throw "Version $Version not found in Mojang manifest." }

    $details = Invoke-RestMethod -Uri $entry.url
    return @{ JarUrl = $details.downloads.server.url; Version = $Version }
}

# === Main Part ===
$serverInfo = Get-ServerJarUrl -Version $MinecraftVersion
$MinecraftVersion = $serverInfo.Version
$InstallDir = "$InstallDir\$MinecraftVersion"
$JavaDir = "$InstallDir\jdk"
$ServerJarPath = "$InstallDir\server.jar"
$EulaPath = "$InstallDir\eula.txt"
$PropsPath = "$InstallDir\server.properties"
$OpsPath = "$InstallDir\ops.json"
$StartPath = "$InstallDir\start.ps1"

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$requiredJava = Get-JavaVersion([version]$MinecraftVersion)
$javaPath = Install-JavaLocally -JavaVersion $requiredJava -TargetDir $JavaDir

Write-Host "Downloading Minecraft server JAR for $MinecraftVersion..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $serverInfo.JarUrl -OutFile $ServerJarPath

Write-Host "Accepting EULA..." -ForegroundColor Magenta
Set-Content -Path $EulaPath -Value "eula=true" -Force

Write-Host "Generating server files (first run)..."
$process = Start-Process -FilePath $javaPath -ArgumentList @("-Xms1G", "-Xmx1G", "-jar", "$ServerJarPath", "nogui") -WorkingDirectory $InstallDir -PassThru
Start-Sleep -Seconds 30
if ($process -and !$process.HasExited) {
    Write-Host "Stopping server after file generation..." -ForegroundColor Yellow
    Stop-Process -Id $process.id -Force
}

Write-Host "Configuring server.properties..." -ForegroundColor Magenta
(Get-Content $PropsPath) | ForEach-Object {
    $line = $_
    foreach ($property in $serverProperties.Keys) {
        if ($line -match "^$property=") {
            return "$property=$($serverProperties[$property])"
        }
    }
    return $line
} | Set-Content $PropsPath

Write-Host "Updating ops.json..." -ForegroundColor Magenta
$opsContent = @"
[{"uuid":"1e77e4bb-b569-3180-bfa2-19e02f0763c2","name":"D_Guy_","level":4,"bypassesPlayerLimit":false}]
"@
Set-Content -Path $OpsPath -Value $opsContent -Force

Write-Host "Creating start script..." -ForegroundColor Magenta
$startContent = @"
`$installDir = "$InstallDir"
`$javaPath = "$javaPath"
`$javaArgs = @("-Xms1G", "-Xmx4G", "-jar", "$ServerJarPath", "nogui")
Start-Process -FilePath "`$javaPath" -ArgumentList `$javaArgs -WorkingDirectory "`$installDir" -WindowStyle Hidden
"@
Set-Content -Path $StartPath -Value $startContent -Force

Write-Host "Creating firewall rules..." -ForegroundColor Magenta
New-NetFirewallRule -DisplayName "Oracle" -Direction Inbound -Protocol TCP -LocalPort 25565 -Action Allow -Profile Any -Enabled True | Out-Null
New-NetFirewallRule -DisplayName "OpenJDK Platform Binary" -Direction Inbound -Program "$javaPath" -Action Allow -Profile Any -Enabled True | Out-Null

Write-Host "`nMinecraft $MinecraftVersion setup complete!" -ForegroundColor Green
if ($Start) {
    Write-Host "Starting Minecraft server..." -ForegroundColor Magenta
    
    Start-Process -FilePath "powershell.exe" -ArgumentList "-File $StartPath" -WindowStyle Hidden
} else {
    Write-Host "Server not running. To start the server manually:" -ForegroundColor Yellow
    Write-Host "Run `"$StartPath`""
}
