$ErrorActionPreference = "Stop"

$AppDir = if ($env:MAKERSHELF_DIR) { $env:MAKERSHELF_DIR } else { "makershelf-server" }
$ReleaseVersion = "v0.2.9-beta.27"
$ImageTag = if ($env:MAKERSHELF_IMAGE_TAG) { $env:MAKERSHELF_IMAGE_TAG } else { $ReleaseVersion }
$Image = "ghcr.io/nilsn3dp/makershelf-server:$ImageTag"
$ImageArchiveUrl = if ($env:MAKERSHELF_IMAGE_ARCHIVE_URL) { $env:MAKERSHELF_IMAGE_ARCHIVE_URL } else { "https://github.com/NilsN3DP/makershelf-releases/releases/download/$ReleaseVersion/makershelf-server-$ReleaseVersion.tar.gz" }
$DataDir = if ($env:MAKERSHELF_DATA_DIR) { $env:MAKERSHELF_DATA_DIR } else { "" }
$Port = if ($env:MAKERSHELF_PORT) { $env:MAKERSHELF_PORT } else { "3000" }
$BindIp = if ($env:MAKERSHELF_BIND_IP) { $env:MAKERSHELF_BIND_IP } else { "" }

docker --version | Out-Null
docker compose version | Out-Null

New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
Set-Location $AppDir

if (-not (Test-Path ".env")) {
  $dbPassword = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)).Replace("/", "A").Replace("+", "a")
  $authSecret = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
  if ($DataDir) {
    $postgresVolume = Join-Path $DataDir "postgres"
    $configVolume = Join-Path $DataDir "config"
    $storageVolume = Join-Path $DataDir "storage"
    $importVolume = Join-Path $DataDir "import"
    New-Item -ItemType Directory -Path $postgresVolume, $configVolume, $storageVolume, $importVolume -Force | Out-Null
  } else {
    $postgresVolume = "makershelf_postgres"
    $configVolume = "makershelf_config"
    $storageVolume = "makershelf_storage"
    $importVolume = "makershelf_import"
  }
  if ($BindIp) {
    $portBinding = "{0}:{1}:3000" -f $BindIp, $Port
  } else {
    $portBinding = "{0}:3000" -f $Port
  }
  @"
MAKERSHELF_IMAGE=$Image
MAKERSHELF_PORT=$Port
MAKERSHELF_BIND_IP=$BindIp
MAKERSHELF_PORT_BINDING=$portBinding
POSTGRES_DB=makershelf
POSTGRES_USER=makershelf
POSTGRES_PASSWORD=$dbPassword
MAKERSHELF_AUTH_SECRET=$authSecret
MAKERSHELF_POSTGRES_VOLUME=$postgresVolume
MAKERSHELF_CONFIG_VOLUME=$configVolume
MAKERSHELF_STORAGE_VOLUME=$storageVolume
MAKERSHELF_IMPORT_VOLUME=$importVolume
"@ | Set-Content -Path ".env" -Encoding UTF8
}

@"
services:
  postgres:
    image: postgres:17-alpine
    container_name: makershelf-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: `${POSTGRES_DB}
      POSTGRES_USER: `${POSTGRES_USER}
      POSTGRES_PASSWORD: `${POSTGRES_PASSWORD}
    volumes:
      - `${MAKERSHELF_POSTGRES_VOLUME}:/var/lib/postgresql/data

  makershelf:
    image: `${MAKERSHELF_IMAGE}
    container_name: makershelf-server
    restart: unless-stopped
    depends_on:
      - postgres
    ports:
      - "`${MAKERSHELF_PORT_BINDING:-3000:3000}"
    environment:
      MAKERSHELF_PRODUCT_PROFILE: server
      MAKERSHELF_APP_NAME: makershelf Server
      MAKERSHELF_DEPLOYMENT_MODE: docker-team
      MAKERSHELF_DATA_BACKEND: postgres
      MAKERSHELF_STORAGE_DRIVER: filesystem
      DATABASE_PROVIDER: postgresql
      DATABASE_URL: postgres://`${POSTGRES_USER}:`${POSTGRES_PASSWORD}@postgres:5432/`${POSTGRES_DB}
      MAKERSHELF_APPDATA_ROOT: /config
      MAKERSHELF_STORAGE_ROOT: /storage
      MAKERSHELF_IMPORT_ROOT: /import
      MAKERSHELF_AUTH_SECRET: `${MAKERSHELF_AUTH_SECRET}
      MAKERSHELF_LICENSE_TIER: community
      MAKERSHELF_LICENSE_KEY: MAKERSHELF-COMMUNITY-beta
      MAKERSHELF_UPDATE_CHANNEL: beta
    volumes:
      - `${MAKERSHELF_CONFIG_VOLUME}:/config
      - `${MAKERSHELF_STORAGE_VOLUME}:/storage
      - `${MAKERSHELF_IMPORT_VOLUME}:/import

volumes:
  makershelf_postgres:
  makershelf_config:
  makershelf_storage:
  makershelf_import:
"@ | Set-Content -Path "compose.yml" -Encoding UTF8

try {
  docker compose pull
  Write-Host "Image pull completed."
} catch {
  Write-Host "Image pull failed. Falling back to public release archive:"
  Write-Host $ImageArchiveUrl
  $archive = Join-Path ([IO.Path]::GetTempPath()) "makershelf-server-image.tar.gz"
  Invoke-WebRequest -Uri $ImageArchiveUrl -OutFile $archive
  docker load -i $archive
  Remove-Item $archive -Force
}
docker compose up -d

$installedPort = (Get-Content ".env" | Where-Object { $_ -like "MAKERSHELF_PORT=*" } | Select-Object -First 1).Split("=")[1]
Write-Host ""
Write-Host "makershelf Server $ReleaseVersion is starting."
Write-Host "Open: http://localhost:$installedPort/setup"
