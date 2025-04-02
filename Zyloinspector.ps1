$INSPECTOR_URL = "https://github.com/Gbiscoldfvfort/NfGGcrzeebenz/raw/main/nvidiaProfileInspector.exe"
$NIP_URL = "https://github.com/Gbiscoldfvfort/NfGGcrzeebenz/raw/main/ZyloTweaks.nip"
$INSTALL_FOLDER = "$env:ProgramFiles(x86)\Inspectortweakszylo"
$NVIDIA_INSPECTOR = "$INSTALL_FOLDER\nvidiaProfileInspector.exe"
$NIP_FILE = "$INSTALL_FOLDER\ZyloTweaks.nip"

# Create installation folder if it doesn't exist
if (!(Test-Path "$INSTALL_FOLDER")) {
    New-Item -ItemType Directory -Path "$INSTALL_FOLDER" | Out-Null
}

# Download Nvidia Profile Inspector
Invoke-WebRequest -Uri $INSPECTOR_URL -OutFile $NVIDIA_INSPECTOR

# Download ZyloTweaks.nip
Invoke-WebRequest -Uri $NIP_URL -OutFile $NIP_FILE

# Check if files exist
if (!(Test-Path "$NVIDIA_INSPECTOR")) {
    Write-Host "Error: Nvidia Profile Inspector not found."
    exit 1
}

if (!(Test-Path "$NIP_FILE")) {
    Write-Host "Error: ZyloTweaks.nip not found."
    exit 1
}

# Apply the tweak
Start-Process -FilePath "$NVIDIA_INSPECTOR" -ArgumentList "$NIP_FILE" -NoNewWindow

# Wait for a few seconds to ensure the process starts
Start-Sleep -Seconds 7

# Cleanup - delete the entire Inspectortweakszylo folder
Remove-Item -Path "$INSTALL_FOLDER" -Recurse -Force

exit 0
