Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore

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

# Scan for games
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

# --- GENERATE MODERN DARK UI ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Steam Bulk Uninstaller" Height="600" Width="450" Background="#171A21" WindowStartupLocation="CenterScreen" FontFamily="Segoe UI">
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <TextBlock Text="SELECT GAMES TO DELETE" Foreground="#66C0F4" FontSize="18" FontWeight="Bold" Margin="0,0,0,15" HorizontalAlignment="Center"/>
        
        <Border Grid.Row="1" Background="#1B2838" CornerRadius="5" Padding="10">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel Name="GamePanel" />
            </ScrollViewer>
        </Border>
        
        <Button Name="NukeBtn" Grid.Row="2" Content="NUKE SELECTED GAMES" Background="#c0392b" Foreground="White" FontSize="14" FontWeight="Bold" Height="45" Margin="0,20,0,0" BorderThickness="0" Cursor="Hand">
            <Button.Resources>
                <Style TargetType="Border">
                    <Setter Property="CornerRadius" Value="5"/>
                </Style>
            </Button.Resources>
        </Button>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$gamePanel = $window.FindName("GamePanel")
$nukeBtn = $window.FindName("NukeBtn")

# Populate the UI with checkboxes for each game
foreach ($game in $installedGames | Sort-Object Name) {
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Content = $game.Name
    $cb.Foreground = "White"
    $cb.FontSize = 14
    $cb.Margin = "5,8,5,8"
    $cb.Tag = $game
    $gamePanel.Children.Add($cb) | Out-Null
}

$script:selectedGamesToNuke = @()

# Button Click Event
$nukeBtn.Add_Click({
    foreach ($cb in $gamePanel.Children) {
        if ($cb.IsChecked) {
            $script:selectedGamesToNuke += $cb.Tag
        }
    }
    $window.Close()
})

# Show the modern window
$window.ShowDialog() | Out-Null

if ($script:selectedGamesToNuke.Count -eq 0) {
    Write-Host "No games selected. Aborting."
    return
}

# --- DELETION LOGIC ---
Write-Host "Closing Steam to prevent file locks..."
Stop-Process -Name steam -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

foreach ($game in $script:selectedGamesToNuke) {
    $gameFolder = Join-Path $game.Library "steamapps\common\$($game.InstallDir)"
    
    Write-Host "Nuking: $($game.Name)..."
    
    if (Test-Path $gameFolder) {
        Remove-Item -Path $gameFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    if (Test-Path $game.ManifestFile) {
        Remove-Item -Path $game.ManifestFile -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`nAll selected games have been permanently deleted! You can now open Steam."