# SHUN HUB installer for Windows. Run it with one line in PowerShell:
#   irm https://www.soulhouseproductions.com/shun/install.ps1 | iex
# It fetches uv (Astral's Python manager) when none is installed, lets uv install Python 3.13 and the Hub as a
# tool, writes install.json so the Hub can update itself, adds a Start Menu entry and starts the Hub.
# Folders: uv.exe in %USERPROFILE%\.local\bin (UV_INSTALL_DIR), the Hub's environment under uv's tool dir
# (UV_TOOL_DIR), shunhub.exe in %USERPROFILE%\.local\bin (UV_TOOL_BIN_DIR), the Hub's data in %LOCALAPPDATA%\ShunHub
# (SHUNHUB_DATA_DIR). SHUN_BOOTSTRAP_URL, SHUNHUB_SHORTCUT_DIR and SHUNHUB_NO_START exist for the tests.
# This file is plain ASCII and holds no secrets. The Hub asks for its GitHub credentials itself, in Settings.
#
# Everything runs inside one script block, so under irm | iex the caller's session keeps none of the preferences,
# functions and variables below (only the TLS setting stays: it belongs to the whole process). Every failure ends as
# a "SHUN HUB: ..." message: the steps throw their own, and the catch at the end puts the prefix on any other error.

& {
    try {
        $ErrorActionPreference = 'Stop'
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        function Say($text) { Write-Host "SHUN HUB: $text" }

        # Every download goes through here, so a failure names the address it was for. With $file the response is saved
        # there, without it the response is returned.
        function Download($url, $file) {
            try {
                if ($file) {
                    Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing
                } else {
                    return Invoke-WebRequest -Uri $url -UseBasicParsing
                }
            } catch {
                throw "SHUN HUB: could not download $url ($($_.Exception.Message))"
            }
        }

        function Get-Json($url) {
            $response = Download $url
            try {
                return ($response.Content | ConvertFrom-Json)
            } catch {
                throw "SHUN HUB: $url is not valid JSON ($($_.Exception.Message))"
            }
        }

        function Pick($value, $default) { if ($value) { return $value } else { return $default } }

        # 1. bootstrap.json says where hub.json is; hub.json says which wheel to install.
        $bootstrapUrls = @()
        if ($env:SHUN_BOOTSTRAP_URL) { $bootstrapUrls += $env:SHUN_BOOTSTRAP_URL }
        $bootstrapUrls += 'https://www.soulhouseproductions.com/shun/bootstrap.json'
        $bootstrapUrls += 'https://raw.githubusercontent.com/shuniverse-dev/shun-releases/main/bootstrap.json'
        $bootstrap = $null
        foreach ($url in $bootstrapUrls) {
            # A miss is only a note and the next address is tried. This is not Get-Json: its errors are whole SHUN HUB:
            # messages, and the note shows just PowerShell's reason. An address that answers without an error is no
            # use either when what it sent has no hub_index: a website that serves bootstrap.json as a download
            # (octet-stream) hands PowerShell bytes instead of text, which ConvertFrom-Json turns into numbers, and
            # {} has none.
            try {
                $candidate = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content | ConvertFrom-Json
                if (($candidate.hub_index -is [string]) -and $candidate.hub_index) {
                    $bootstrap = $candidate
                    Say "reading $url"
                    break
                }
                Say "no hub_index in $url"
            } catch {
                Say "no bootstrap.json at $url ($($_.Exception.Message))"
            }
        }
        if ($null -eq $bootstrap -or -not $bootstrap.hub_index) { throw 'SHUN HUB: bootstrap.json could not be read from any of its locations.' }
        $index = Get-Json $bootstrap.hub_index
        if (-not $index.version -or -not $index.wheel -or -not $index.sha256) { throw 'SHUN HUB: hub.json is incomplete.' }
        $wheelName = [IO.Path]::GetFileName(([Uri]$index.wheel).AbsolutePath)
        if ($wheelName -ne "shunhub-$($index.version)-py3-none-any.whl") { throw "SHUN HUB: $wheelName is not the Hub wheel for version $($index.version)." }
        Say "installing SHUN HUB $($index.version)"

        # 2. uv: the one already on this computer, or the latest release from Astral.
        $uvDir = Pick $env:UV_INSTALL_DIR (Join-Path $env:USERPROFILE '.local\bin')
        $uv = Join-Path $uvDir 'uv.exe'
        if (-not (Test-Path $uv)) {
            $found = Get-Command uv.exe -ErrorAction SilentlyContinue
            if ($found) { $uv = $found.Source }
        }
        if (-not (Test-Path $uv)) {
            $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
            $zipUrl = "https://github.com/astral-sh/uv/releases/latest/download/uv-$arch-pc-windows-msvc.zip"
            Say "fetching uv from $zipUrl"
            $zip = Join-Path ([IO.Path]::GetTempPath()) 'shunhub-uv.zip'
            Download $zipUrl $zip
            New-Item -ItemType Directory -Force -Path $uvDir | Out-Null
            Expand-Archive -Path $zip -DestinationPath $uvDir -Force
            Remove-Item -Path $zip -Force
            $uv = Join-Path $uvDir 'uv.exe'
        }
        if (-not (Test-Path $uv)) { throw "SHUN HUB: uv.exe is not at $uv after the download." }
        Say "using uv at $uv"

        # 3. The wheel, verified against the checksum in hub.json, installed as a uv tool with Python 3.13.
        $downloads = Join-Path ([IO.Path]::GetTempPath()) 'shunhub-install'
        New-Item -ItemType Directory -Force -Path $downloads | Out-Null
        $wheel = Join-Path $downloads $wheelName
        Say "downloading $wheelName"
        Download $index.wheel $wheel
        $hash = (Get-FileHash -Path $wheel -Algorithm SHA256).Hash.ToLower()
        if ($hash -ne $index.sha256.ToLower()) {
            Remove-Item -Path $wheel -Force
            throw 'SHUN HUB: the downloaded wheel does not match the checksum in hub.json; nothing was installed.'
        }
        Say 'installing Python 3.13 and the Hub (a few minutes the first time)'
        $ErrorActionPreference = 'Continue'
        & $uv tool install --python 3.13 --force $wheel
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($code -ne 0) { throw "SHUN HUB: uv tool install failed with exit code $code." }
        Remove-Item -Path $wheel -Force -ErrorAction SilentlyContinue

        # 4. install.json for the Hub's own updates, and a Start Menu entry.
        $binDir = Pick $env:UV_TOOL_BIN_DIR (Join-Path $env:USERPROFILE '.local\bin')
        $launcher = Join-Path $binDir 'shunhub.exe'
        if (-not (Test-Path $launcher)) { throw "SHUN HUB: $launcher was not created by uv." }
        $dataDir = Pick $env:SHUNHUB_DATA_DIR (Join-Path $env:LOCALAPPDATA 'ShunHub')
        New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
        $info = [ordered]@{ method = 'uv-tool'; uv = $uv; launcher = $launcher } | ConvertTo-Json
        [IO.File]::WriteAllText((Join-Path $dataDir 'install.json'), $info, (New-Object Text.UTF8Encoding $false))
        $menuDir = Pick $env:SHUNHUB_SHORTCUT_DIR (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
        New-Item -ItemType Directory -Force -Path $menuDir | Out-Null
        $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $menuDir 'SHUN HUB.lnk'))
        $shortcut.TargetPath = $launcher
        $shortcut.WorkingDirectory = $binDir
        $shortcut.Description = 'SHUN HUB, the Shuniverse launch station'
        $shortcut.Save()

        # 5. Start it.
        Say "installed SHUN HUB $($index.version). Start it from the Start Menu (SHUN HUB) or run $launcher"
        if (-not $env:SHUNHUB_NO_START) { Start-Process -FilePath $launcher }
    } catch {
        if ($_.Exception.Message -like 'SHUN HUB:*') { throw } else { throw "SHUN HUB: $($_.Exception.Message)" }
    }
}
