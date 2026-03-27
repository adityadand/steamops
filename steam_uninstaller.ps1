# Find the main Steam installation path
$steamReg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue
if (-not $steamReg) {
    [System.Windows.MessageBox]::Show("Steam path not found.", "Error")
    return
}
$steamPath = $steamReg.SteamPath -replace '/', '\'
$libraryFoldersFile = Join-Path $steamPath "steamapps\libraryfolders.vdf"
$libraryPaths = @("$steamPath")

# Find other library drives
if (Test-Path $libraryFoldersFile) {
    $vdfContent = Get-Content $libraryFoldersFile
    $paths = $vdfContent | Select-String -Pattern '"path"\s+"([^"]+)"' | ForEach-Object { $_.Matches.Groups[1].Value -replace '\\\\', '\' }
    $libraryPaths += $paths
}

$installedGames = @()

# Scan for games and find their exact folder names
foreach ($lib in $libraryPaths | Select-Object -Unique) {
    $manifestPath = Join-Path $lib "steamapps"
    if (Test-Path $manifestPath) {
        $manifests = Get-ChildItem -Path $manifestPath -Filter "appmanifest_*.acf"
        foreach ($file in $manifests) {
            $content = Get-Content $file.FullName | Out-String
            if ($content -match '"appid"\s+"(\d+)"') { $appId = $matches[1] }
            if ($content -match '"name"\s+"([^"]+)"') { $name = $matches[1] }
            if ($content -match '"installdir"\s+"([^"]+)"') { $installDir = $matches[1] }
            
            if ($appId -and $name -and $installDir -and $name -ne "Steamworks Common Redistributables") {
                $installedGames += [PSCustomObject]@{
                    Name = $name
                    AppID = $appId
                    Library = $lib
                    InstallDir = $installDir
                    ManifestFile = $file.FullName
                }
            }
        }
    }
}

if ($installedGames.Count -eq 0) {
    Write-Host "No games found."
    return
}

# Generate the multi-select GUI
$selectedGames = $installedGames | Sort-Object Name | Out-GridView -Title "Select Games to PERMANENTLY DELETE (Hold CTRL for multiple)" -PassThru

if (-not $selectedGames) {
    Write-Host "No games selected. Aborting."
    return
}

# Close Steam first so it doesn't get confused when files disappear
Write-Host "Closing Steam..."
Stop-Process -Name steam -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Directly delete the game folders and manifest files
foreach ($game in $selectedGames) {
    $gameFolder = Join-Path $game.Library "steamapps\common\$($game.InstallDir)"
    
    Write-Host "Deleting: $($game.Name)..."
    
    # Delete the actual game files
    if (Test-Path $gameFolder) {
        Remove-Item -Path $gameFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Delete the manifest file so Steam knows it's uninstalled
    if (Test-Path $game.ManifestFile) {
        Remove-Item -Path $game.ManifestFile -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Done! You can now open Steam."