# Path to Rw.exe
$rwePath = "C:\Program Files\RW-Everything\Rw.exe"

# Global settings for lowest latency
$globalInterval = 0x80000000  # Set to 0 for lowest latency
$globalHCSPARAMSOffset = 0x4  # Standard HCSPARAMS offset
$globalRTSOFFOffset = 0x0  # Runtime offset

function Dec-To-Hex($decimal) {
    return "0x" + $decimal.ToString("X")
}

function Get-Device-Addresses() {
    $deviceMap = @{}
    $resources = Get-WmiObject -Class Win32_PNPAllocatedResource -Namespace root\CIMV2

    foreach ($resource in $resources) {
        if ($resource.Dependent -match '"([^"]+)"' -and $resource.Antecedent -match '"([^"]+)"') {
            $deviceId = $Matches[1]
            $physicalAddress = $Matches[1]
            if ($deviceId -match "^[A-Za-z0-9\\]+$" -and $physicalAddress -match "^[A-Fa-f0-9]+$") {
                $deviceMap[$deviceId] = [convert]::ToUInt64($physicalAddress, 16)
            }
        }
    }
    return $deviceMap
}

function Is-Admin() {
    return (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Apply-Tweaks() {
    $success = $true

    if (-not (Is-Admin)) {
        Write-Host "Administrator privileges are required." -ForegroundColor Red
        Start-Sleep -Seconds 1
        return 1
    }

    if (-not (Test-Path $rwePath)) {
        Write-Host "RW-Everything not found at '$rwePath'. Please check the path." -ForegroundColor Red
        Start-Sleep -Seconds 1
        return 1
    }

    Stop-Process -Name "Rw" -ErrorAction SilentlyContinue
    $deviceMap = Get-Device-Addresses

    foreach ($xhciController in Get-WmiObject Win32_USBController) {
        if ($xhciController.ConfigManagerErrorCode -eq 22) { continue }

        $deviceId = $xhciController.DeviceID
        if (-not $deviceMap.ContainsKey($deviceId)) { continue }

        $capabilityAddress = $deviceMap[$deviceId]
        $opBase = $capabilityAddress  # Operation Base Address

        # Halt Controller (USBCMD.RS=0)
        $usbcmd = [Convert]::ToUInt32((& $rwePath /Min /NoLogo /Stdout /Command="R32 $(Dec-To-Hex $opBase)"), 16)
        $usbcmd = $usbcmd -band (-bnot 1)  # Clear RS bit (bit 0)
        & $rwePath /Min /NoLogo /Stdout /Command="W32 $(Dec-To-Hex $opBase) $usbcmd"

        # Get HCSPARAMS and RTSOFF values
        $hcsparamsValue = & $rwePath /Min /NoLogo /Stdout /Command="R32 $((Dec-To-Hex ($capabilityAddress + $globalHCSPARAMSOffset)))" | ForEach-Object {
            if ($_ -match '0x([0-9A-Fa-f]+)') { return [convert]::ToUInt32($Matches[1], 16) }
        }
        if ($hcsparamsValue -eq $null) { continue }

        $maxIntrs = ($hcsparamsValue -shr 16) -band 0xFF
        $rtsoffValue = & $rwePath /Min /NoLogo /Stdout /Command="R32 $((Dec-To-Hex ($capabilityAddress + $globalRTSOFFOffset)))" | ForEach-Object {
            if ($_ -match '0x([0-9A-Fa-f]+)') { return [convert]::ToUInt32($Matches[1], 16) }
        }
        if ($rtsoffValue -eq $null) { continue }

        $runtimeAddress = $capabilityAddress + $rtsoffValue

        # Port-Specific Tuning (Disable port suspend timeouts)
        $portscAddr = $runtimeAddress + 0x400
        $portsc = [Convert]::ToUInt32((& $rwePath /Min /NoLogo /Stdout /Command="R32 $(Dec-To-Hex $portscAddr)"), 16)
        $portsc = $portsc -band (-bnot (0xF -shl 5))  # Clear PLS field (bits 5-8)
        & $rwePath /Min /NoLogo /Stdout /Command="W32 $(Dec-To-Hex $portscAddr) $portsc"

        # Doorbell Optimization (Trigger immediate processing)
        $doorbellAddr = $runtimeAddress + 0x00
        & $rwePath /Min /NoLogo /Stdout /Command="W32 $(Dec-To-Hex $doorbellAddr) 0x00000001"

        # Extended Capabilities Tweaks (Disable ASPM)
        $extCapAddr = $capabilityAddress + 0x1000
        $aspmReg = [Convert]::ToUInt32((& $rwePath /Min /NoLogo /Stdout /Command="R32 $(Dec-To-Hex $extCapAddr)"), 16)
        $aspmReg = $aspmReg -band (-bnot 0x03)  # Clear ASPM L0s/L1 bits
        & $rwePath /Min /NoLogo /Stdout /Command="W32 $(Dec-To-Hex $extCapAddr) $aspmReg"

        # Apply Low-Latency Configuration to Interrupters
        for ($i = 0; $i -lt $maxIntrs; $i++) {
            $interrupterAddress = Dec-To-Hex ($runtimeAddress + 0x24 + (0x20 * $i))
            & $rwePath /Min /NoLogo /Stdout /Command="W32 $interrupterAddress $globalInterval"

            # Verify
            $readBackValue = & $rwePath /Min /NoLogo /Stdout /Command="R32 $interrupterAddress" | ForEach-Object {
                if ($_ -match '0x([0-9A-Fa-f]+)') { return [convert]::ToUInt32($Matches[1], 16) }
            }
            if ($readBackValue -ne $globalInterval) {
                Write-Host "Failed to set low-latency config at $interrupterAddress." -ForegroundColor Red
                $success = $false
            }
        }

        # Restart Controller (USBCMD.RS=1)
        $usbcmd = $usbcmd -bor 1
        & $rwePath /Min /NoLogo /Stdout /Command="W32 $(Dec-To-Hex $opBase) $usbcmd"
    }

    if ($success) {
        Write-Host "XHCI tweaks successfully applied!" -ForegroundColor Green
    } else {
        Write-Host "Some configurations failed. Check logs above." -ForegroundColor Yellow
    }

    Start-Sleep -Seconds 1
    return 0
}

Apply-Tweaks
