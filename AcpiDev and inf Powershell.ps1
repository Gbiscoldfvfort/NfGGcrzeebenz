#Requires -RunAsAdministrator

# Function to take ownership and rename file
function Process-File($file, $suffix) {
    try {
        # Take ownership
        takeown /f $file.FullName
        Write-Host "Taken ownership of: $($file.FullName)"

        # Set ACL for Administrators
        icacls $file.FullName /grant Administrators:F
        Write-Host "Updated permissions for: $($file.FullName)"

        # Rename file
        $newName = Join-Path $file.DirectoryName "AcpiDev.$suffix"
        Rename-Item -Path $file.FullName -NewName $newName -Force
        Write-Host "Renamed to: $newName"
        Write-Host "------------------------------------"
    }
    catch {
        Write-Host "Error processing $($file.FullName): $_" -ForegroundColor Red
    }
}

# Main script
Write-Host "Starting search for AcpiDev.sys and AcpiDev.inf files..." -ForegroundColor Cyan

# Get all fixed drives and search for files
Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
    $drive = $_.DeviceID
    Write-Host "Searching drive $drive..." -ForegroundColor Yellow
    
    # Search for both file types
    Get-ChildItem -Path "$drive\" -Recurse -Include "AcpiDev.sys", "AcpiDev.inf" -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "Found file at: $($_.FullName)" -ForegroundColor Green
        
        # Determine suffix based on file type
        if ($_.Name -eq "AcpiDev.sys") {
            $suffix = "BAK"
        } else {
            $suffix = "BAK2"
        }
        
        Process-File -File $_ -Suffix $suffix
    }
}

Write-Host "Operation completed. Please verify system stability." -ForegroundColor Cyan