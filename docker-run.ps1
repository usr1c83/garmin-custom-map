<#
Запуск пайплайна в Docker на «чистом» Windows (PowerShell, без bash).
  .\docker-run.ps1 --config config/examples/test-chernyakhovsk.env
  $env:REGION_NAME="suzdal"; $env:REGION_QUERY="Суздальский район"; `
    $env:GEOFABRIK="central-fd"; .\docker-run.ps1
#>
$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

$image = if ($env:IMAGE) { $env:IMAGE } else { "garmin-custom-map" }

docker image inspect $image *> $null
if ($LASTEXITCODE -ne 0 -or $env:REBUILD -eq "1") {
    Write-Host ">> building Docker image $image"
    docker build -t $image .
    if ($LASTEXITCODE -ne 0) { throw "docker build failed" }
}

$envArgs = @()
$vars = @("REGION_NAME","REGION_QUERY","BBOX","BOUNDARY_GEOJSON","GEOFABRIK",
          "CONTOUR_STEP","INCLUDE_CADASTRE","CADASTRE_GEOJSON","CADASTRE_INSECURE","CADASTRE_PROXY",
          "WITH_SEA","WITH_BOUNDS","JAVA_XMX","HGT_SOURCE","MKGMAP_VERSION",
          "SPLITTER_VERSION","REFRESH_OSM")
foreach ($v in $vars) {
    $val = [Environment]::GetEnvironmentVariable($v)
    if ($val) { $envArgs += @("-e", "$v=$val") }
}

$pwdPath = (Get-Location).Path
docker run --rm -v "${pwdPath}:/work" @envArgs $image ./run_all.sh @args
exit $LASTEXITCODE
