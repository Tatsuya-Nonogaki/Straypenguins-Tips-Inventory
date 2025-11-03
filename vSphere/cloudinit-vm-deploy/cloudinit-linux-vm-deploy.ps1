<#
.SYNOPSIS
  Automated vSphere Linux VM deployment using cloud-init seed ISO.
  Version: 0.0.4546C

.DESCRIPTION
  Automate deployment of a Linux VM from template VM, leveraging cloud-init, in 4 phases:
    (1) Automatic Cloning
    (2) Clone Initialization
    (3) Kick Cloud-init Start
    (4) Close & Clean up (detach ISO, remove seed ISO on DataStore, and optionally disable cloud-init)
  Uses a YAML parameter file (see vm-settings_example.yaml).

  **Requirements:**
  * vSphere virtual machine environment (8+ recommended)
  * VMware PowerCLI
  * powershell-yaml module
  * mkisofs: ISO creator command; Redefine the variable in "Global variables"
    section if you want to use an alternative (with appropriate option flags).

  **Exit codes:**
    0: Success
    1: General runtime error (VM operations, PowerCLI, etc)
    2: System/environment/file error (directory/file creation, etc)
    3: Bad arguments or parameter/config input

.PARAMETER Phase
  (Alias -p) List of steps (1,2,3,4) to execute. e.g. -Phase 1,2,3,4 or -Phase 2

.PARAMETER Config
  (Alias -c) Path to YAML parameter file for the VM deployment.

.PARAMETER NoRestart
  If set, disables auto-poweron/shutdown except when multi-phase is needed.

.PARAMETER NoCloudReset
  (Alias -noreset) If set, disables creation of /etc/cloud/cloud-init.disabled in Phase 4.
  ISO detachment and ISO file removal are always performed in Phase 4.

.EXAMPLE
  .\cloudinit-linux-vm-deploy.ps1 -Phase 1,2,3,4 -Config .\params\vm-settings.yaml
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(1,2,3,4)]
    [Alias("p")]
    [int[]]$Phase,

    [Parameter(Mandatory)]
    [Alias("c")]
    [string]$Config,

    [Parameter()]
    [switch]$NoRestart,

    [Parameter()]
    [Alias("noreset")]
    [switch]$NoCloudReset
)

#
# ---- Global variables ----
#
$scriptdir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$spooldir = Join-Path $scriptdir "spool"

$mkisofs = "C:\work\cdrtfe\tools\cdrtools\mkisofs.exe"
$seedIsoName = "cloudinit-linux-seed.iso"
$workDirOnVM = "/run/cloudinit-vm-deploy"

# vCenter connection variables
$vcport = 443
$connRetry = 2
$connRetryInterval = 5

if (-not (Test-Path $spooldir)) {
    Write-Host "Error: $spooldir does not exist. Please create it before running this script." -ForegroundColor Red
    Exit 2
}

if (-Not (Get-Module VMware.VimAutomation.Core)) {
    Write-Host "Loading vSphere PowerCLI. This may take a while..."
    Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
}

Import-Module powershell-yaml -ErrorAction Stop

# ---- Phase argument check ----
$phaseSorted = $Phase | Sort-Object
for ($i=1; $i -lt $phaseSorted.Count; $i++) {
    if ($phaseSorted[$i] -ne $phaseSorted[$i-1] + 1) {
        Write-Host "Error: Invalid -Phase sequence (missing phase between $($phaseSorted[$i-1]) and $($phaseSorted[$i]))." -ForegroundColor Red
        Exit 3
    }
}

# ---- Resolve collision between NoRestart and multi-phase execution ----
if ($phaseSorted.Count -gt 1 -and $NoRestart) {
    Write-Host "Warning: Both multiple phases and -NoRestart are specified." -ForegroundColor Yellow
    Write-Host "Automatic power on/off is required for multi-phase execution."
    $resp = Read-Host "Proceed and ignore -NoRestart? (y/[N])"
    if ($resp -ne "y" -and $resp -ne "Y") {
        Write-Host "Operation cancelled by user."
        Exit 3
    }
    Write-Log -Warn "-NoRestart ignored due to multi-phase execution (user confirmed)."
    $NoRestart = $false
}

# LogFilePath (temporary)
$LogFilePath = Join-Path $spooldir "deploy.log"

function Write-Log {
    param(
        [string]$Message,
        [switch]$Error,
        [switch]$Warn
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -Append -FilePath $LogFilePath -Encoding UTF8

    if ($Error) {
        Write-Host $Message -ForegroundColor Red
    } elseif ($Warn) {
        Write-Host $Message -ForegroundColor Yellow
    } else {
        Write-Host $Message
    }
}

function ConvertToSecureStringFromPlain {
    param(
        [Parameter()]
        [string]$PlainText
    )

    if (-not $PlainText -or $PlainText.Trim().Length -eq 0) {
        Write-Verbose "ConvertToSecureStringFromPlain: no password supplied."
        return $null
    }

    try {
        $secure = $PlainText | ConvertTo-SecureString -AsPlainText -Force -ErrorAction Stop
        return $secure
    } catch {
        Write-Log -Error "ConvertToSecureStringFromPlain: ConvertTo-SecureString failed: $_"
        return $null
    }
}

function VIConnect {
    # expects $vcserver, $vcuser, $vcpasswd in global scope
    process {
        for ($i = 1; $i -le $connRetry; $i++) {
            try {
                if ([string]::IsNullOrEmpty($vcuser) -or [string]::IsNullOrEmpty($vcpasswd)) {
                    Write-Log "Connect-VIServer $vcserver -Port $vcport -Force"
                    Connect-VIServer $vcserver -Port $vcport -Force -WarningAction SilentlyContinue -ErrorAction Continue -ErrorVariable myErr
                } else {
                    Write-Log "Connect-VIServer $vcserver -Port $vcport -User $vcuser -Password ******** -Force"
                    Connect-VIServer $vcserver -Port $vcport -User $vcuser -Password $vcpasswd -Force -WarningAction SilentlyContinue -ErrorAction Continue -ErrorVariable myErr
                }
                if ($?) { break }
            } catch {
                Write-Log -Warn "Failed to connect (attempt $i): $_"
            }
            if ($i -eq $connRetry) {
                Write-Log -Error "Connection attempts exceeded retry limit"
                Exit 1
            }
            Write-Host "Waiting $connRetryInterval sec. before retry.." -ForegroundColor Yellow
            Start-Sleep -Seconds $connRetryInterval
        }
    }
}


# ---- Get-VM with short retries to tolerate transient vCenter/API glitches ----
function TryGet-VMObject {
    # VM argument may be either object or name
    param(
        [Parameter()]$VM,
        [int]$MaxAttempts = 3,
        [int]$IntervalSec = 2,
        [switch]$Quiet
    )

    if (-not $VM) {
        Write-Log -Error "TryGet-VMObject: invalid VM object passed."
        return $null
    }

    if ($VM -is [string]) {
        $vmName = $VM
    } elseif ($VM -and $VM.PSObject.Properties.Match('Name')) {
        $vmName = $VM.Name
    } else {
        $vmName = $VM.ToString()
    }

    $attempt = 0
    while ($attempt -lt $MaxAttempts) {
        try {
            if ($VM -is [string]) {
                $vmObject = Get-VM -Name $VM -ErrorAction Stop
            } else {
                if ($VM.PSObject.Properties.Match('Id')) {
                    $vmObject = Get-VM -Id $VM.Id -ErrorAction Stop
                } elseif ($VM.PSObject.Properties.Match('Name')) {
                    $vmObject = Get-VM -Name $VM.Name -ErrorAction Stop
                } else {
                    throw "Invalid VM object: missing Id/Name property"
                }
            }
            return $vmObject
        } catch {
            $attempt++
            Write-Verbose "TryGet-VMObject: attempt #$attempt failed for '$vmName': $_"
            if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds $IntervalSec }
        }
    }
    if (-not $Quiet) {
        Write-Log -Error "TryGet-VMObject: failed to obtain VM object after $MaxAttempts attempts for input '$vmName'"
    }
    return $null
}

# ---- VM Power On/Off Functions ----
function Start-MyVM {
    param(
        [Parameter()]$VM,
        [switch]$Force,
        [int]$WaitPowerSec = 60,
        [int]$WaitToolsSec = 120
    )

    if (-not $VM) {
        Write-Log -Error "Start-MyVM: invalid VM object passed."
        return "start-failed"
    }

    # VM argument may be either object or name as TryGet-VMObject resolves it
    if ($VM -is [string]) {
        $vmName = $VM
    } elseif ($VM -and $VM.PSObject.Properties.Match('Name')) {
        $vmName = $VM.Name
    } else {
        $vmName = $VM.ToString()
    }

    # Refresh VM object
    $vmObj = TryGet-VMObject $VM
    if (-not $vmObj) {
        Write-Log -Error "Start-MyVM: unable to refresh VM object: '$vmName'"
        return "stat-unknown"
    }

    # Respect NoRestart unless Force overrides
    if (-not $Force -and $NoRestart) {
        if ($vmObj.PowerState -eq "PoweredOn") {
            Write-Log "NoRestart specified but VM is already powered on: '$vmName'"
            return "already-started"
        } else {
            Write-Log "NoRestart specified: VM remains powered off."
            return "skipped"
        }
    }

    # If already on, check tools
    if ($vmObj.PowerState -eq "PoweredOn") {
        Write-Log "VM already powered on: '$vmName'"
        $toolsOk = Wait-ForVMwareTools -VM $vmObj -TimeoutSec $WaitToolsSec
        if ($toolsOk) {
            return "already-started"
        } else {
            Write-Log -Warn "But VMware Tools did not become ready on already-on VM: '$vmName'"
            return "timeout"
        }
    }

    # Start the VM
    Write-Log "Starting VM '$vmName'..."
    try {
        $null = Start-VM -VM $vmObj -Confirm:$false -ErrorAction Stop
    } catch {
        Write-Log -Error "Failed to start VM '$vmName': $_"
        return "start-failed"
    }

    # Wait for PoweredOn and VMware Tools readiness
    $elapsed = 0
    $interval = 5
    $refreshFailCount = 0
    $maxRefreshConsecutiveFails = 3
    while ($elapsed -lt $WaitPowerSec) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        $vmObj = TryGet-VMObject $vmObj 1 0
        if (-not $vmObj) {
            $refreshFailCount++
            Write-Verbose "Start-MyVM: transient refresh failure for '$vmName' while waiting (#$refreshFailCount)"
            if ($refreshFailCount -ge $maxRefreshConsecutiveFails) {
                Write-Log -Warn "Start-MyVM: repeated failures refreshing VM object for '$vmName' while waiting; aborting."
                return "start-failed"
            }
            continue
        } else {
            $refreshFailCount = 0
        }

        # Wait for VMware Tools
        if ($vmObj.PowerState -eq "PoweredOn") {
            Write-Log "VM '$vmName' is now PoweredOn. Waiting for VMware Tools..."
            $toolsOk = Wait-ForVMwareTools -VM $vmObj -TimeoutSec $WaitToolsSec
            if ($toolsOk) {
                return "success"
            } else {
                return "timeout"
            }
        }
        Write-Verbose "Waiting for VM '$vmName' to reach PoweredOn... ($elapsed/$WaitPowerSec s)"
    }
    Write-Log -Error "Timeout waiting for VM '$vmName' to reach PoweredOn after $WaitPowerSec s."
    return "start-failed"
}

function Stop-MyVM {
    param(
        [Parameter()]$VM,
        [int]$TimeoutSeconds = 180
    )

    if (-not $VM) {
        Write-Log -Error "Stop-MyVM: invalid VM object passed."
        return "stop-failed"
    }

    # VM argument may be either object or name as TryGet-VMObject resolves it
    if ($VM -is [string]) {
        $vmName = $VM
    } elseif ($VM -and $VM.PSObject.Properties.Match('Name')) {
        $vmName = $VM.Name
    } else {
        $vmName = $VM.ToString()
    }

    if ($NoRestart) {
       Write-Log "NoRestart specified: Shutdown was skipped."
       return "skipped"
    }

    # Refresh current state to get current PowerState
    $vmObj = TryGet-VMObject $VM
    if (-not $vmObj) {
        Write-Log -Error "Stop-MyVM: failed to refresh VM object for '$vmName' after retries."
        return "stat-unknown"
    }

    if ($vmObj.PowerState -eq "PoweredOff") {
        Write-Log "VM already powered off: '$vmName'"
        return "already-stopped"
    }

    Write-Log "Shutting down VM: '$vmName'"
    try {
        $null = Stop-VM -VM $vmObj -Confirm:$false -ErrorAction Stop
    } catch {
        Write-Log -Warn "Failed to stop VM '$vmName': $_"
        return "stop-failed"
    }

    # Wait for powered off
    $elapsed = 0
    $interval = 5
    $refreshFailCount = 0
    $maxRefreshConsecutiveFails = 3
    while ($elapsed -lt $TimeoutSeconds) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        $vmObj = TryGet-VMObject $vmObj 1 0
        if (-not $vmObj) {
            $refreshFailCount++
            Write-Verbose "Stop-MyVM: transient refresh failure for '$vmName' while waiting (#$refreshFailCount)"
            if ($refreshFailCount -ge $maxRefreshConsecutiveFails) {
                Write-Log -Warn "Stop-MyVM: repeated failures refreshing VM object for '$vmName' while waiting; aborting."
                return "stop-failed"
            }
            continue
        } else {
            $refreshFailCount = 0
        }

        if ($vmObj.PowerState -eq "PoweredOff") {
            Write-Log "VM is now powered off: $vmName"
            return "success"
        }
        Write-Verbose "Waiting for VM '$vmName' to power off... ($elapsed/$TimeoutSeconds s)"
    }

    Write-Log -Error "Timeout waiting for VM '$vmName' to reach PoweredOff after $TimeoutSeconds seconds."
    return "timeout"
}

# Wait for VMware Tools to become ready inside the VM
function Wait-ForVMwareTools {
    param(
        [Parameter()]$VM,
        [int]$TimeoutSec = 120,
        [int]$PollIntervalSec = 5
    )

    if (-not $VM) {
        Write-Log -Warn "Wait-ForVMwareTools: VM parameter is null or empty."
        return $false
    }
    if ($TimeoutSec -le 0) { $TimeoutSec = 5 }
    if ($PollIntervalSec -le 0) { $PollIntervalSec = 1 }

    if ($VM -is [string]) {
        $vmName = $VM
    } elseif ($VM -and $VM.PSObject.Properties.Match('Name')) {
        $vmName = $VM.Name
    } else {
        $vmName = $VM.ToString()
    }

    # Refresh VM object
    $vmObj = TryGet-VMObject $VM
    if (-not $vmObj) {
        Write-Log -Warn "Wait-ForVMwareTools: cannot refresh VM object: '$vmName'"
        return $false
    }

    $waited = 0
    while ($waited -lt $TimeoutSec) {
        try {
            $toolsStatus = $vmObj.ExtensionData.Guest.ToolsStatus
        } catch {
            # transient failure reading ExtensionData; attempt to refresh and continue
            Write-Verbose "Wait-ForVMwareTools: failed to read ToolsStatus for '$vmName': $_"
            $vmObj = TryGet-VMObject $vmObj 1 0
            if (-not $vmObj) {
                Write-Verbose "Wait-ForVMwareTools: transient refresh failed for '$vmName'"
            }
            Start-Sleep -Seconds $PollIntervalSec
            $waited += $PollIntervalSec
            continue
        }

        if ($toolsStatus -eq "toolsOk") {
            Write-Log "VMware Tools is running on VM: '$vmName' (waited ${waited}s)"
            return $true
        }

        Start-Sleep -Seconds $PollIntervalSec
        $waited += $PollIntervalSec

        # Refresh VM object with minimal retries to keep status current
        $vmObj = TryGet-VMObject $vmObj 1 0
        if (-not $vmObj) {
            Write-Verbose "Wait-ForVMwareTools: transient refresh failure for '$vmName' while waiting (waited ${waited}s)"
        }
    }

    # Final status read attempt
    try {
        $finalName = $vmObj.Name
        $finalStatus = $vmObj.ExtensionData.Guest.ToolsStatus
    } catch {
        $finalName = $vmName
        $finalStatus = $null
    }

    Write-Log -Warn "Timed out waiting for VMware Tools on VM: '$vmName' after ${TimeoutSec}s. Last known status:: Name: $($finalName), ToolsStatus: $($finalStatus)"
    return $false
}

# ---- Load parameter file ----
if (-not (Test-Path $Config)) {
    Write-Host "Parameter file not found: $Config" -ForegroundColor Red
    Exit 3
}
try {
    $params = ConvertFrom-Yaml (Get-Content $Config -Raw)
} catch {
    Write-Host "Failed to parse YAML: $Config" -ForegroundColor Red
    Exit 3
}

$new_vm_name = $params.new_vm_name

# ---- Resolve working directory ----
$workdir = Join-Path $spooldir $new_vm_name
if (-not (Test-Path $workdir)) {
    try {
        New-Item -ItemType Directory -Path $workdir | Out-Null
        Write-Log "Created VM output directory: $workdir"
    } catch {
        Write-Log -Error "Failed to create workdir ($workdir): $_"
        Exit 2
    }
}
$LogFilePath = Join-Path $workdir ("deploy-" + (Get-Date -Format 'yyyyMMdd') + ".log")

# ---------------------------------------
# ---- Main processing begins from here
# ---------------------------------------

# Connect to vCenter
$vcserver = $params.vcenter_host
$vcuser   = $params.vcenter_user
$vcpasswd = $params.vcenter_password
VIConnect

# ---- Clone Template VM to the target VM with specified spec ----
function AutoClone {
    Write-Log "=== Phase 1: Automatic Cloning ==="

    # Check if a VM with the same name already exists
    $existingVM = TryGet-VMObject $new_vm_name -Quiet
    if ($existingVM) {
        Write-Log -Error "A VM with the same name '$new_vm_name' already exists. Aborting deployment."
        Exit 2
    }

    # Clone
    $templateVM = Get-Template -Name $params.template_vm_name
    if (-not $templateVM) {
        Write-Log -Error "Specified VM Template not found: $($params.template_vm_name)"
        Exit 3
    }

    if ([string]::IsNullOrEmpty($params.resource_pool_name) -or $params.resource_pool_name -eq "Resources") {
        $resourcePool = (Get-Cluster -Name $params.cluster_name | Get-ResourcePool | Where-Object { $_.Name -eq "Resources" })
    } else {
        $resourcePool = (Get-Cluster -Name $params.cluster_name | Get-ResourcePool | Where-Object { $_.Name -eq $params.resource_pool_name })
        if (-not $resourcePool) {
            Write-Log -Error "Specified Resource Pool not found: $($params.resource_pool_name)"
            Exit 3
        }
    }

    $vmParams = @{
        Name         = $new_vm_name
        Template     = $templateVM
        ResourcePool = $resourcePool
        Datastore    = $params.datastore_name
        VMHost       = $params.esxi_host
        ErrorAction  = 'Stop'
    }

    if ($params.disk_format) {
        $vmParams['DiskStorageFormat'] = $params.disk_format
    }

    if ($params.dvs_portgroup) {
        # For Distributed Switch
        $pg = Get-VDPortgroup -Name $params.dvs_portgroup
        if (-not $pg) {
            Write-Log -Error "Specified Distributed Portgroup not found: $($params.dvs_portgroup)"
            Exit 3
        }
        $vmParams['Portgroup'] = $pg
    }
    elseif ($params.network_name) {
        # For standard switch
        $pg = Get-VirtualPortGroup -Name $params.network_name
        if (-not $pg) {
            Write-Log -Error "Specified Standard Portgroup not found: $($params.network_name)"
            Exit 3
        }
        $vmParams['NetworkName'] = $params.network_name
    }

    try {
        $newVM = New-VM @vmParams | Tee-Object -Variable newVMOut
        $newVMOut | Out-File $LogFilePath -Append -Encoding UTF8
        Write-Log "Deployed new VM: $($newVM.Name) from template: $($params.template_vm_name) in $($params.datastore_name)"
    } catch {
        Write-Log -Error "Error occurred while deploying VM: '$new_vm_name': $_"
        Exit 1
    }

    # CPU/mem
    try {
        Set-VM -VM $newVM -NumCpu $params.cpu -MemoryMB $params.memory_mb -Confirm:$false -ErrorAction Stop |
          Tee-Object -Variable setVMOut | Out-File $LogFilePath -Append -Encoding UTF8
        Write-Log "Set CPU: $($params.cpu), Mem: $($params.memory_mb) MB"
    } catch {
        Write-Log -Error "Error during CPU/memory set: $_"
        Exit 1
    }

    # Disks
    if ($params.disks) {
        foreach ($d in $params.disks) {
            if ($d.ContainsKey('name') -and $d.ContainsKey('size_gb')) {
                $disk = Get-HardDisk -VM $newVM | Where-Object { $_.Name -eq $d['name'] }
                if ($disk -and $disk.CapacityGB -lt $d['size_gb']) {
                    try {
                        Set-HardDisk -HardDisk $disk -CapacityGB $d['size_gb'] -Confirm:$false |
                          Tee-Object -Variable setHDOut | Out-File $LogFilePath -Append -Encoding UTF8
                        Start-Sleep -Seconds 2
                        Write-Log "Resized disk `"$($disk.Name)`" to $($d['size_gb']) GB"
                    } catch {
                        Write-Log -Error "Error resizing disk `"$($d['name'])`": $_"
                        Exit 1
                    }
                }
            } else {
                Write-Log -Warn "Skipping disk entry missing 'name' or 'size_gb': $($d | Out-String)"
            }
        }
    }

    Write-Log "Phase 1 complete"
}

# ---- Initialize the clone VM for Phase-3 kickstart ----
function InitializeClone {
    Write-Log "=== Phase 2: Guest Initialization ==="

    $vm = TryGet-VMObject $new_vm_name
    if (-not $vm) {
        Write-Log -Error "VM not found: '$new_vm_name'"
        Exit 1
    }

    # Prepare username and password for VM commands
    $guestUser = $params.username
    $guestPassPlain = $params.password
    $guestPass = ConvertToSecureStringFromPlain $guestPassPlain
    if (-not $guestPass) {
        Write-Log -Error "Failed to convert guest password to SecureString. Aborting in Phase-2."
        Exit 3
    }

    # Prepare the initialization script
    $localInitPath = Join-Path $scriptdir "scripts/init-vm-cloudinit.sh"
    if (-not (Test-Path $localInitPath)) {
        Write-Log -Error "Required script not found: $localInitPath"
        Exit 2
    }

    # Boot-up the clone VM
    if ($NoRestart) {
        if ($vm.PowerState -ne "PoweredOn") {
            Write-Host "'-NoRestart' is specified, but VM must be powered on for initialization."
            $resp = Read-Host "Start VM anyway? [Y]/n (If you answer N, the entire script will abort here)"
            if ($resp -eq "" -or $resp -eq "Y" -or $resp -eq "y") {
                $vmStartStatus = Start-MyVM $vm -Force
            } else {
                Write-Log -Error "User aborted due to NoRestart restriction."
                Exit 1
            }
        } else {
            # No prompt; delegate further processing and messaging to Start-MyVM
            $vmStartStatus = Start-MyVM $vm -Force
        }
    } else {
        $vmStartStatus = Start-MyVM $vm
    }

    Write-Log "VM boot/init status: `"$vmStartStatus`""

    # Use a pass/fail sentinel ($toolsOk) to decide whether we continue.
    # Only explicit "passing" cases set $toolsOk = $true; everything else will remain false and be treated as failure.
    $toolsOk = $false

    switch ($vmStartStatus) {
        "success" {
            # Start-MyVM guarantees VMware Tools readiness before returning success.
            $toolsOk = $true
        }
        "already-started" {
            # Start-MyVM returned this when VM was already on and Tools were ready.
            $toolsOk = $true
        }

        <#
        "skipped" {
            # NOTE: This case is intentionally commented out because, in the current InitializeClone flow,
            # Start-MyVM is invoked with -Force whenever -NoRestart is set (or the user explicitly agreed to start).
            # Therefore Start-MyVM should not return "skipped" from this call path; the "skipped" return value
            # is reachable in other phases/call-sites (e.g., Phase-3 Stop/Start operations) and is therefore
            # left implemented in Start-MyVM itself. We keep this commented block here for documentation / future
            # reference and to make it easy to re-enable handling if the calling logic changes later.
            Write-Log "VM was not started due to -NoRestart option. Check current status of the VM and VMware Tools."
        }
        #>

        "timeout" {
            Write-Log -Warn "VMware Tools did not become ready within expected timeframe. Initialization cannot proceed reliably."
        }
        "start-failed" {
            Write-Log -Error "VM could not be started. Initialization aborted."
        }
        "stat-unknown" {
            Write-Log -Error "Unable to determine VM state (stat-unknown). Initialization aborted."
        }
        default {
            Write-Log -Warn "Unrecognized VM start status: `"$vmStartStatus`". Aborting to avoid undefined behaviour."
        }
    }

    # Final gating logic: proceed only when $toolsOk was set by an accepted success case.
    if (-not $toolsOk) {
        Write-Log -Error "Script aborted since VM is not ready for online activities."
        Exit 1
    }

    # Refresh VM object for reliable operations
    $vm = TryGet-VMObject $vm
    if (-not $vm) {
        Write-Log -Error "Unable to refresh VM object: '$($vm.Name)'"
        Exit 1
    }

    # Ensure guest workdir
    $guestInitPath = "$workDirOnVM/init-vm-cloudinit.sh"
    try {
        $phase2cmd = @"
sudo /bin/bash -c "mkdir -p $workDirOnVM && chown $guestUser $workDirOnVM"
"@
        $null = Invoke-VMScript -VM $vm -ScriptText $phase2cmd -ScriptType Bash `
            -GuestUser $guestUser -GuestPassword $guestPass -ErrorAction Stop
        Write-Log "Ensured work directory exists on the VM: $workDirOnVM"
    } catch {
        Write-Log -Error "Failed to create work directory on the VM: $_"
        Exit 1
    }

    # Transfer the script and run on the clone
    try {
        $null = Copy-VMGuestFile -LocalToGuest -Source $localInitPath -Destination $guestInitPath `
            -VM $vm -GuestUser $guestUser -GuestPassword $guestPass -Force -ErrorAction Stop
        Write-Log "Copied init script to the VM: $guestInitPath"
    } catch {
        Write-Log -Error "Failed to copy script to the VM: $_"
        Exit 1
    }

    try {
        $phase2cmd = @"
chmod +x $guestInitPath && sudo /bin/bash $guestInitPath
"@
        $null = Invoke-VMScript -VM $vm -ScriptText $phase2cmd -ScriptType Bash `
            -GuestUser $guestUser -GuestPassword $guestPass -ErrorAction Stop
        Write-Log "Executed init script on the VM. Output: $($result.ScriptOutput)"
    } catch {
        Write-Log -Error "Failed to execute init script on the VM: $_"
        Exit 1
    }

    try {
        $null = Invoke-VMScript -VM $vm -ScriptText "rm -f $guestInitPath" -ScriptType Bash `
            -GuestUser $guestUser -GuestPassword $guestPass -ErrorAction Stop
        Write-Log "Removed init script from the VM: $guestInitPath"
    } catch {
        Write-Log -Warn "Failed to remove init script from the VM: $_"
    }

    Write-Log "Phase 2 complete"

    if ($Phase -notcontains 3) {
        Write-Log "Note: The VM has been left powered on. When you are finished, you may shut it down manually; otherwise it will be shut down automatically when Phase-3 begins."
    }
}

# ---- Generate cloud-init seed ISO and personalize VM ----
function CloudInitKickStart {
    Write-Log "=== Phase 3: Cloud-init Seed Generation & Personalization ==="

    function Replace-Placeholders {
    # Replace each placeholder with a value from YAML key or nested hash key (array keys are not supported for now)
        Param(
            [parameter(Mandatory=$true)]
            [String]$template,
            [parameter(Mandatory=$true)]
            [Object]$params,
            [parameter()]
            [String]$prefix = ""
        )

        foreach ($k in $params.Keys) {
            $v = $params[$k]
            $keyPath = if ($prefix) { "$prefix.$k" } else { $k }
            if (
                $v -is [string] -or
                $v -is [int] -or
                $v -is [bool] -or
                $v -is [double] -or
                $null -eq $v
            ) {
                $pattern = "{{\s*$keyPath\s*}}"
                if ($template -match $pattern) {
                    Write-Log "Replacing placeholder: '$keyPath'"
                    $template = $template -replace $pattern, [string]$v
                }
            } elseif ($v -is [hashtable] -or $v -is [PSCustomObject]) {
                $template = Replace-Placeholders -template $template -params $v -prefix $keyPath
            } else {
                $typeName = $v.GetType().Name
                Write-Log "Placeholder replacement skipped unsupported data structure for this script: $keyPath (type: $typeName)"
            }
        }
        return $template
    }

    $vm = TryGet-VMObject $new_vm_name
    if (-not $vm) {
        Write-Log -Error "Target VM not found: '$new_vm_name'"
        Exit 1
    }

    # Prepare username and password for VM commands
    $guestUser = $params.username
    $guestPassPlain = $params.password
    $guestPass = ConvertToSecureStringFromPlain $guestPassPlain
    if (-not $guestPass) {
        Write-Log -Error "Failed to convert guest password to SecureString. Aborting in Phase-3."
        Exit 3
    }

    # --- Early check for /etc/cloud/cloud-init.disabled; if the file exists Phase-3 is meaningless
    $vm = TryGet-VMObject $vm

    if ($vm -and $vm.PowerState -eq 'PoweredOn') {
        $toolsOk = Wait-ForVMwareTools -VM $vm -TimeoutSec 20 -PollIntervalSec 2

        if (-not $toolsOk) {
            Write-Log -Warn "VMware Tools not available to perform early cloud-init.disabled check; proceeding with Phase-3 anyway."
        } else {
            # One-line guest command to check for /etc/cloud/cloud-init.disabled
            $checkCmd = "sudo /bin/bash -c 'if [ -f /etc/cloud/cloud-init.disabled ]; then echo CLOUDINIT_DISABLED; exit 0; else echo CLOUDINIT_ENABLED; exit 1; fi'"

            try {
                $res = Invoke-VMScript -VM $vm -GuestUser $guestUser -GuestPassword $guestPass `
                    -ScriptText $checkCmd -ScriptType Bash -ErrorAction Stop

                $out = if ($res.ScriptOutput) { ($res.ScriptOutput -join [Environment]::NewLine).Trim() } `
                       elseif ($res.ScriptError) { ($res.ScriptError -join [Environment]::NewLine).Trim() } `
                       else { "" }

                if ($res.ExitCode -eq 0 -and $out -match 'CLOUDINIT_DISABLED') {
                    Write-Log -Warn "VM has /etc/cloud/cloud-init.disabled; Phase-3 (seed attach and kickstart) is unnecessary and may be harmful. Aborting Phase-3."
                    Exit 2
                } else {
                    Write-Log "Early check: no /etc/cloud/cloud-init.disabled found on the VM; proceeding with Phase-3."
                }
            } catch {
                Write-Log -Warn "Early check for cloud-init.disabled failed (Invoke-VMScript error): $_"
                Write-Log -Warn "Proceeding with Phase-3 anyway; note if the VM actually has cloud-init disabled, Phase-3 may be ineffective."
            }
        }
    } else {
        Write-Log -Warn "VM is not powered on; unable to check /etc/cloud/cloud-init.disabled. Proceeding with Phase-3."
    }

    # 1. Shutdown the VM (skipped automatically if applicable)
    if (-not $NoRestart) {
        Write-Log "The target VM is going to shut down to attach cloud-config seed ISO and boot for actual personalization to take effect."
        Write-Log "Shutting down in 5 seconds..."
        Start-Sleep -Seconds 5
    }

    $stopResult = Stop-MyVM $vm

    switch ($stopResult) {
        "success" {
            Write-Log "Proceeding with Phase-3 operations."
            # Refresh VM object to ensure we have current PowerState for later steps
            $vm = TryGet-VMObject $vm
        }
        "already-stopped" {
            Write-Log "Proceeding with Phase-3 operations."
            $vm = TryGet-VMObject $vm
        }
        "skipped" {
            Write-Log "Continuing without shutdown."
            $vm = TryGet-VMObject $vm
            if ($vm) { Write-Log "VM power state: $($vm.PowerState)" }
            Write-Log "Note: Ensure the VM power state is appropriate for your needs in this run of Phase-3."
        }
        "timeout" {
            Write-Log -Error "Script aborted."
            Exit 1
        }
        "stop-failed" {
            Write-Log -Error "Script aborted."
            Exit 1
        }
        default {
            Write-Log -Error "Unknown result from Stop-MyVM: '$stopResult'. Script aborted."
            Exit 1
        }
    }

    # 2. Prepare seed working dir
    $seedDir = Join-Path $workdir "cloudinit-seed"
    if (Test-Path $seedDir) {
        try {
            Remove-Item -Recurse -Force $seedDir -ErrorAction Stop
            Write-Log "Removed old seed dir: $seedDir"
        } catch {
            Write-Log -Warn "Failed to remove previous seed dir: $_"
        }
    }
    try {
        New-Item -ItemType Directory -Path $seedDir | Out-Null
        Write-Log "Created seed dir: $seedDir"
    } catch {
        Write-Log -Error "Failed to create seed dir: $_"
        Exit 2
    }

    # 3. Generate user-data/meta-data/network-config from templates
    $tplDir = Join-Path $scriptdir "templates"
    $seedFiles = @(
        @{tpl="user-data_template.yaml"; out="user-data"},
        @{tpl="meta-data_template.yaml"; out="meta-data"}
    )
    # Optional: network-config
    $netTpl = Join-Path $tplDir "network-config_template.yaml"
    if (Test-Path $netTpl) {
        $seedFiles += @{tpl="network-config_template.yaml"; out="network-config"}
    }

    $guestUser = $params.username

    foreach ($f in $seedFiles) {
        $tplPath = Join-Path $tplDir $f.tpl
        $charLF = "`n"
        if (-not (Test-Path $tplPath)) {
            Write-Log -Error "Missing template: $tplPath"
            Exit 2
        }
        try {
            $template = Get-Content $tplPath -Raw

            # For user-data only: construct the filesystem resizing runcmd blocks by substitution
            if ($f.out -eq "user-data") {
                $runcmdList = @()

                # 1. Ext2/3/4 filesystems expansion ===
                if ($params.resize_fs -and $params.resize_fs.Count -gt 0) {
                    foreach ($fsdev in $params.resize_fs) {
                        $runcmdList += @("[ resize2fs, $fsdev ]")
                    }
                }

                # 2. Swap devices expansion ===
                if ($params.resize_swap -and $params.resize_swap.Count -gt 0) {
                    $swapdevs = $params.resize_swap -join " "

                    # Bash script for swap reinit (dividing into parts to avoid PowerShell variable expansion)
                    $shBodyPart = @'
      #!/bin/bash
      set -eux
      for swapdev in 
'@
                    $shBodyTail = @'
      ; do
        OLDUUID=$(blkid -s UUID -o value "$swapdev")
        OLDSWAPUNIT=$(systemd-escape "dev/disk/by-uuid/$OLDUUID").swap
        systemctl mask "$OLDSWAPUNIT"
        swapoff "$swapdev"
        mkswap "$swapdev"
        NEWUUID=$(blkid -s UUID -o value "$swapdev")
        sed -i "s|UUID=$OLDUUID|UUID=$NEWUUID|" /etc/fstab
        systemctl daemon-reload
        systemctl unmask "$OLDSWAPUNIT"
        swapon "$swapdev"
      done
      dracut -f
'@
                    $shBody = $shBodyPart + "$swapdevs" + $shBodyTail

                    # Compose the here-document runcmd entry
                    # By packaging the generated shell script as a here-document for cloud-init runcmd,
                    # complex tasks are delegated to the target VM for reliable execution, avoiding extensive escaping.
                    $swapScriptCmd = @"
|
      bash -c 'cat <<"EOF" >$workDirOnVM/resize_swap.sh
$shBody
      EOF
      '
"@

                    $runcmdList += @("[ mkdir, -p, $workDirOnVM ]")
                    $runcmdList += @("[ chown, $guestUser, $workDirOnVM ]")
                    $runcmdList += @($swapScriptCmd)
                    $runcmdList += @("[ bash, $workDirOnVM/resize_swap.sh ]")

                    $dev = $params.netif1["netdev"]
                    if ($params.netif1["ignore-auto-routes"]) {         # Not set if the key does not exist or the value is false/no/$null
                        $cmd = @"
[ nmcli, connection, modify, "System $dev", ipv4.ignore-auto-routes, yes ]
"@
                        $runcmdList += @($cmd)
                    }
                    if ($params.netif1["ignore-auto-dns"]) {
                        $cmd = @"
[ nmcli, connection, modify, "System $dev", ipv4.ignore-auto-dns, yes ]
"@
                        $runcmdList += @($cmd)
                    }
                    $cmd = @"
[ nmcli, device, reapply, $dev ]
"@
                    $runcmdList += @($cmd)
                }

                # Compose final USER_RUNCMD_BLOCK for template
                if ($runcmdList.Count -gt 0) {
                    $userRuncmdBlock = $runcmdList -join "`n  - "
                    $userRuncmdBlock = "`n  - " + $userRuncmdBlock
                } else {
                    $userRuncmdBlock = " []"
                }

                $template = $template -replace "{{USER_RUNCMD_BLOCK}}", $userRuncmdBlock
                Write-Log "USER_RUNCMD_BLOCK placeholder replaced (count: $($runcmdList.Count))"
            }

            $output = Replace-Placeholders $template $params

            # Write out the file contents, avoiding Set-Content's default behavior of appending a trailing CRLF
            $output = $output.TrimEnd("`r", "`n") + $charLF
            $seedOut = Join-Path $seedDir $f.out
            $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($seedOut, $output, $utf8NoBomEncoding)
            Write-Log "Generated $($f.out) for cloud-init"
        } catch {
            Write-Log -Error "Failed to render $($f.tpl): $_"
            Exit 2
        }
    }

    # 4. Create seed ISO with mkisofs
    if (-not (Test-Path $mkisofs)) {
        Write-Log -Error "ISO creation tool not found: $mkisofs"
        Exit 2
    }
    $isoPath = Join-Path $workdir $seedIsoName

    $cmd = "`"$mkisofs`" -output `"$isoPath`" -V cidata -r -J `"$seedDir`""
    Write-Log "Executing command: $cmd"
    $mkisofsOut = cmd /c $cmd 2>&1
    if (-not (Test-Path $isoPath)) {
        Write-Log -Error "Failed to generate ${isoName}: $mkisofsOut"
        Exit 2
    } else {
        Write-Log "cloud-init seed ISO successfully created: $isoPath"
    }

    # 5. Upload ISO to vSphere datastore and attach to VM's CD drive
    $cdd = Get-CDDrive -VM $vm
    if (-not $cdd) {
        Write-Log -Error "No CD/DVD drive found on this VM. Please add a CD/DVD drive and rerun Phase-3."
        Exit 2
    }

    $seedIsoCopyStore = $params.seed_iso_copy_store.TrimEnd('/').TrimEnd('\')
    $datacenterName = $params.datacenter_name
    if (-not $seedIsoCopyStore) {
        Write-Log -Error "Parameter 'seed_iso_copy_store' is not set. Please check your parameter file."
        Exit 2
    }
    if (-not $datacenterName) {
        Write-Log -Error "Parameter 'datacenter_name' is not set. Please check your parameter file."
        Exit 2
    }

    # Datastore full path like [COMMSTORE01] ISO/cloudinit-seed.iso
    $datastoreIsoPath = "$seedIsoCopyStore/$seedIsoName"

    # Split into datastore name and folder path
    if ($seedIsoCopyStore -match "^\[(.+?)\]\s*(.+)$") {
        $datastoreName = $matches[1]
        $datastoreFolder = $matches[2].Trim('/')
    } else {
        Write-Log -Error "Invalid format for parameter 'seed_iso_copy_store': $seedIsoCopyStore"
        Exit 2
    }

    try {
        $datastore = Get-Datastore -Name $datastoreName -ErrorAction Stop
    } catch {
        Write-Log -Error "Datastore not found: $datastoreName"
        Exit 2
    }

    $vmstoreFolderPath = "vmstore:\$datacenterName\$datastoreName\$datastoreFolder"
    $vmstoreIsoPath = "$vmstoreFolderPath\$seedIsoName"

    # Pre-checks for upload
    if (-not (Test-Path $vmstoreFolderPath)) {
        Write-Log -Error "Target folder does not exist in datastore: $vmstoreFolderPath ($seedIsoCopyStore)"
        Exit 2
    }

    if (Test-Path $vmstoreIsoPath) {
        Write-Log -Error "Seed ISO '$vmstoreIsoPath' ($datastoreIsoPath) already exists. Please remove it or specify another path."
        Exit 2
    }

    # Upload the ISO to the datastore using vmstore:\ path as destination
    try {
        $null = Copy-DatastoreItem -Item "$isoPath" -Destination "$vmstoreIsoPath" -ErrorAction Stop
        Write-Log "Seed ISO uploaded to datastore: '$vmstoreIsoPath' ($datastoreIsoPath)"
    } catch {
        Write-Log -Error "Failed to upload seed ISO to datastore: $_"
        Exit 2
    }

    # Attach ISO to the VM's CD drive
    try {
        $null = Set-CDDrive -CD $cdd -IsoPath "$datastoreIsoPath" -StartConnected $true -Confirm:$false -ErrorAction Stop |
          Tee-Object -Variable setCDOut
          $setCDOut | Select-Object IsoPath,Parent,ConnectionState | Format-List | Out-File $LogFilePath -Append -Encoding UTF8
        Write-Log "Seed ISO attached to the VM's CD drive."
    } catch {
        Write-Log -Error "Failed to attach the seed ISO to the VM's CD drive: $_"
        try {
            $null = Remove-DatastoreItem -Path $vmstoreIsoPath -Confirm:$false -ErrorAction Stop
            Write-Log "Cleaned up the uploaded seed ISO from datastore: '$vmstoreIsoPath'"
        } catch {
            Write-Log -Error "Failed to clean up ISO from datastore after attach failure: $_"
        }
        Exit 1
    }

    # Record epoch seconds right after attaching the seed ISO to reference later in determination of cloud-init completion.
    $seedAttachEpoch = [int][double]((Get-Date).ToUniversalTime() - (Get-Date "1970-01-01T00:00:00Z")).TotalSeconds
    Write-Verbose "Recorded seed attach epoch '$seedAttachEpoch' for later cloud-init completion checks."

    # 6. Power on VM for personalization
    $vmStartStatus = Start-MyVM $vm

    Write-Verbose "Phase-3: Start-MyVM returned status: '$vmStartStatus'"

    # Use a pass/fail sentinel ($toolsOk) to decide whether we continue.
    $toolsOk = $false

    switch ($vmStartStatus) {
        "success" {
            $toolsOk = $true
        }
        "already-started" {
            $toolsOk = $true
        }
        "skipped" {
            Write-Log -Warn "VM was NOT started due to -NoRestart option. Seed ISO was attached to the VM's CD drive."
            Write-Log -Warn "Because the VM was not booted, cloud-init-based personalization will NOT be applied in this run."
            Write-Log -Warn "Powering-on the VM later will apply the planned changes; this is now operator responsibility."
        }
        "timeout" {
            Write-Log -Warn "VMware Tools did not become ready within expected timeframe. Personalization may fail; aborting."
        }
        "start-failed" {
            Write-Log -Error "VM could not be started. Aborting Phase-3."
        }
        "stat-unknown" {
            Write-Log -Error "Unable to determine VM state (stat-unknown). Aborting Phase-3."
        }
        default {
            Write-Log -Warn "Unknown result from Start-MyVM: `"$vmStartStatus`". Aborting to avoid undefined behaviour."
        }
    }

    # Final gating logic: proceed only when $toolsOk was set by an accepted success case.
    if (-not $toolsOk) {
        if ($vmStartStatus -eq "skipped") {
            # If the user requested Phase-4 in the same run and cloud-reset is expected,
            # we must not continue to Phase-4 when the VM hasn't actually been booted here.
            if ($Phase -contains 4 -and -not $NoCloudReset) {
                Write-Log -Error "Script aborted since VM is not ready for the online activities in Phase 4 (seed ISO attached but VM not started due to -NoRestart)"
                Exit 2
            }

            Write-Log "Phase 3 complete with -NoRestart (seed ISO created and attached; VM not started due to the option)"
            return
        } else {
            Write-Log -Error "Script aborted since VM is not ready for online activities."
            Exit 1
        }
    }

    # When VM was not started by this phase since it was already running
    if ($vmStartStatus -eq "already-started" -and $Phase -contains 4 -and -not $NoCloudReset) {
        Write-Log -Warn "VM was already powered on before seed ISO attach; cloud-init was NOT applied in this run."
        Write-Log -Warn "Phase-4 would remove the seed without applying changes. Aborting."
        Exit 2
    }

    # 7. Wait for cloud-init to complete personalization on the VM

    # Refresh VM object for reliable operations.
    $vm = TryGet-VMObject $vm
    if (-not $vm) {
        Write-Log -Error "Unable to refresh VM object after VM start; aborting."
        Exit 1
    }
    Write-Verbose "Phase-3: VM object refreshed successfully: '$($vm.Name)'"

    # Wait for VMware Tools then stabilize to avoid transient early Tools
    $backoffSec = if ($params.cloudinit_backoff_sec) { [int]$params.cloudinit_backoff_sec } else { 60 }
    $toolsOk = Wait-ForVMwareTools -VM $vm -TimeoutSec 120
    if (-not $toolsOk) {
        Write-Log -Warn "VMware Tools did not report ready within 120s; will still attempt copy with retries."
    }
    Write-Log "Pausing ${backoffSec}s to allow guest services to stabilize..."
    Start-Sleep -Seconds $backoffSec

    #--- Quick check before the real cloud-init completion polling, in order to avoid pointless wait in case cloud-init was not invoked on this boot.

    # Build Quick-check script locally then transfer to the VM and utilize.
    $localQuickPath = Join-Path $workdir "quick-check.sh"
    $guestQuickPath = "$workDirOnVM/quick-check.sh"

    # quick-check guest script template (inspect several files and return evidence)
    $quickCheckTpl = @'
#!/bin/bash
SEED_TS="{{SEED_TS}}"

# Argument SEED_TS must be numeric
if ! [[ "$SEED_TS" =~ ^[0-9]+$ ]]; then
  echo "TERMINAL:INVALID_SEED_TS:'$SEED_TS'"
  exit 2
fi

# Function to determine current instance-id trying multiple methods in order
get_instance_id() {
  local res ins target latest

  # 1) cloud-init query
  if command -v cloud-init >/dev/null 2>&1; then
    res=$(cloud-init query instance_id 2>/dev/null || cloud-init query instance-id 2>/dev/null || echo "")
    if [ -n "$res" ]; then
      # remove surrounding quotes and trim
      ins=$(printf "%s" "$res" | tr -d '"' | tr -d "'" | xargs)
      if [ -n "$ins" ]; then
        echo "$ins"
        return 0
      fi
    fi
  fi

  # 2) /run cloud-init runtime location
  if [ -f /run/cloud-init/.instance-id ]; then
    ins=$(cat /run/cloud-init/.instance-id 2>/dev/null | xargs)
    if [ -n "$ins" ]; then
      echo "$ins"
      return 0
    fi
  fi

  # 3) legacy/data location
  if [ -f /var/lib/cloud/data/instance-id ]; then
    ins=$(cat /var/lib/cloud/data/instance-id 2>/dev/null | xargs)
    if [ -n "$ins" ]; then
      echo "$ins"
      return 0
    fi
  fi

  # 4) /var/lib/cloud/instance is often a symlink to instances/<id>
  if [ -L /var/lib/cloud/instance ]; then
    target=$(readlink -f /var/lib/cloud/instance 2>/dev/null)
    if [ -n "$target" ]; then
      echo "$(basename "$target")"
      return 0
    fi
  fi

  # 5) fallback: the most-recent /var/lib/cloud/instances/<id> directory
  latest=$(find /var/lib/cloud/instances -maxdepth 1 -mindepth 1 -type d -printf "%T@ %p\n" | sort -rn | head -n1 | cut -d' ' -f2)
  if [ -n "$latest" ]; then
    echo "$(basename "$latest")"
    return 0
  fi

  return 1
}

# Function to check file mtime > seed; label is second arg
check_mtime_after() {
  paths="$1"
  label="$2"
  for f in $paths; do
    [ -e "$f" ] || continue
    file_ts=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    if [ "$file_ts" -gt "$SEED_TS" ]; then
      echo "${label}:$f${instanceIdStr:-}"
      exit 0
    fi
  done
}

##--- Start validation ---

# Get current instance-id if possible
inst=""
instanceIdStr=""
inst=$(get_instance_id 2>/dev/null || echo "")
if [ -n "$inst" ]; then
  instanceIdStr=";$inst"
fi

# 0) Terminal: cloud-init explicitly disabled
if [ -f /etc/cloud/cloud-init.disabled ]; then
  echo "TERMINAL:cloud-init-disabled"
  exit 2
fi

# 1) strong evidence: instance-id files (try common locations)
check_mtime_after '/var/lib/cloud/data/instance-id' RAN
check_mtime_after '/run/cloud-init/.instance-id' RAN

# Check /var/lib/cloud/instances/<id>/, where cloud/instance/ is often a symlink to it.
# If we already discovered an instance id, prefer directly checking it.
if [ -n "$inst" ] && [ -d "/var/lib/cloud/instances/$inst" ]; then
  check_mtime_after "/var/lib/cloud/instances/$inst" RAN
else
  if [ -L /var/lib/cloud/instance ]; then
    inst_link_target=$(readlink -f /var/lib/cloud/instance 2>/dev/null)
    if [ -n "$inst_link_target" ]; then
      check_mtime_after "$inst_link_target" RAN
    fi
  fi
fi

# 2) very strong: sem files (module-level evidence)
if [ -n "$inst" ]; then
  semdir="/var/lib/cloud/instances/$inst/sem"
  if [ -d "$semdir" ]; then
    for s in "$semdir"/*; do
      [ -e "$s" ] || continue
      file_ts=$(stat -c %Y "$s" 2>/dev/null || echo 0)
      if [ "$file_ts" -gt "$SEED_TS" ]; then
        echo "RAN-SEM:$s${instanceIdStr:-}"
        exit 0
      fi
    done
  fi
fi

# 3) strong evidence: cloud-init logs
check_mtime_after /var/log/cloud-init.log RAN
check_mtime_after /var/log/cloud-init-output.log RAN

# 4) boot-finished (fallback)
check_mtime_after /var/lib/cloud/instance/boot-finished RAN

# 5) supporting evidence: network config artifacts
check_mtime_after '/etc/sysconfig/network-scripts/ifcfg-*' RAN-NET
check_mtime_after '/etc/NetworkManager/system-connections/*' RAN-NET
check_mtime_after '/etc/netplan/*.yaml' RAN-NET
check_mtime_after '/etc/systemd/network/*.network' RAN-NET
check_mtime_after '/etc/network/interfaces' RAN-NET

# nothing found
echo "NOTRAN"
exit 1
'@

    # Confirm VMware Tools availability first
    $toolsAvailableForQuickCheck = Wait-ForVMwareTools -VM $vm -TimeoutSec 20 -PollIntervalSec 5

    # Ensure guest workdir
    try {
        $phase3cmd = @"
sudo /bin/bash -c "mkdir -p $workDirOnVM && chown $guestUser $workDirOnVM"
"@
        $null = Invoke-VMScript -VM $vm -ScriptText $phase3cmd -GuestUser $guestUser -GuestPassword $guestPass `
            -ScriptType Bash -ErrorAction Stop
        Write-Log "Ensured work directory exists on the VM: $workDirOnVM"
    } catch {
        Write-Log -Error "Failed to ensure work directory on the VM: $_"
        Remove-Item -Path $localQuickPath -ErrorAction SilentlyContinue
        Exit 1
    }

    if (-not $toolsAvailableForQuickCheck) {
        Write-Log -Warn "VMware Tools not available for quick-check; cannot reliably detect whether cloud-init ran for this attach. Proceeding to cloud-init completion polling as a fallback."
    } else {
        # Replace placeholder and write local script (guest expects LF line endings)
        $qcContent = $quickCheckTpl.Replace('{{SEED_TS}}', [string]$seedAttachEpoch)
        Set-Content -Path $localQuickPath -Value $qcContent -Encoding UTF8 -Force
        # normalize CRLF -> LF and write as UTF-8 without BOM
        $txt = Get-Content -Raw -Path $localQuickPath -Encoding UTF8
        $txt = $txt -replace "`r`n", "`n"
        $txt = $txt -replace "`r", "`n"
        [System.IO.File]::WriteAllText($localQuickPath, $txt, (New-Object System.Text.UTF8Encoding($false)))
        Write-Verbose "Wrote local quick-check script: $localQuickPath"

        # Copy quick-check script to the VM
        $maxQCAttempts = 3
        $qcAttempt = 0
        $qcCopied = $false
        while (-not $qcCopied -and $qcAttempt -lt $maxQCAttempts) {
            $qcAttempt++
            try {
                $null = Copy-VMGuestFile -LocalToGuest -Source $localQuickPath -Destination $guestQuickPath `
                    -VM $vm -GuestUser $guestUser -GuestPassword $guestPass -Force -ErrorAction Stop
                $phase3cmd = @"
sudo /bin/bash -c "chmod +x $guestQuickPath"
"@
                $null = Invoke-VMScript -VM $vm -ScriptText $phase3cmd -ScriptType Bash `
                    -GuestUser $guestUser -GuestPassword $guestPass -ErrorAction Stop
                $qcCopied = $true
                Write-Verbose "Copied quick-check script to the VM ($guestQuickPath) (attempt $qcAttempt)"
            } catch {
                Write-Verbose "Copy-VMGuestFile for quick-check failed (attempt $qcAttempt): $_"
                # try waiting for tools briefly and retry
                $toolsOk2 = Wait-ForVMwareTools -VM $vm -TimeoutSec 10 -PollIntervalSec 2
                if (-not $toolsOk2) {
                    Write-Verbose "VMware Tools still unavailable; sleeping before next quick-check copy attempt..."
                    Start-Sleep -Seconds 5
                } else {
                    Write-Verbose "VMware Tools recovered; retrying quick-check copy..."
                }
            }
        }

        # Remove local quick script regardless, while keeping guest copy for execution
        Remove-Item -Path $localQuickPath -ErrorAction SilentlyContinue

        $qcExecuted = $false

        if (-not $qcCopied) {
            Write-Log -Warn "Failed to upload quick-check script to the VM after $maxQCAttempts attempts; as a fallback, proceeding to normal cloud-init completion polling without quick-check."
        } else {
            # Execute quick-check on guest and collect output
            try {
                Write-Log "Executing quick-check script on the VM to collect clout-init base status..."
                $qcExecCmd = "sudo /bin/bash '$guestQuickPath'"
                $qcRes = Invoke-VMScript -VM $vm -ScriptText $qcExecCmd -ScriptType Bash `
                    -GuestUser $guestUser -GuestPassword $guestPass -ErrorAction Stop
                $qcExecuted = $true
            } catch {
                Write-Log -Warn "Quick-check execution failed (Invoke-VMScript error): $_. Proceeding with normal cloud-init completion polling."
            }

            if ($qcExecuted) {
                # Collect stdout primarily and use stderr as fallback; optionally log stderr.
                $qcStdout = ""
                $qcStderr = ""
                if ($qcRes.ScriptOutput -and $qcRes.ScriptOutput.Count -gt 0) {
                    $qcStdout = ($qcRes.ScriptOutput -join [Environment]::NewLine).Trim()
                } elseif ($qcRes.ScriptError -and $qcRes.ScriptError.Count -gt 0) {
                    $qcStderr = ($qcRes.ScriptError -join [Environment]::NewLine).Trim()
                    Write-Verbose "quick-check stderr: $qcStderr"
                    $qcStdout = $qcStderr
                }

                # take first non-empty line from qcStdout (guard against multi-line noise)
                $firstLine = ""
                if ($qcStdout) {
                    $firstLine = ($qcStdout -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 1).Trim()
                }

                # Extract required fields: label, path, optional instance-id if contained in qcStdout
                $currentInstanceId = $null
                $evidencePath = $null
                $label = $null

                if ($firstLine -and ($firstLine -match '^(?<label>[^:]+):(?<path>[^;]+)(?:;(?<inst>.+))?$')) {
                    $label = $matches['label']
                    $evidencePath = $matches['path'].Trim()
                    if ($matches['inst']) { $currentInstanceId = $matches['inst'].Trim() }
                    Write-Verbose "quick-check parsed: label=$label, evidence=$evidencePath, instance=$currentInstanceId"
                } elseif ($firstLine) {
                    # unexpected format; log for diagnostics
                    Write-Verbose "quick-check: unrecognized stdout format: '$firstLine'"
                }

                # Log instance id if present
                if ($currentInstanceId) {
                    Write-Log "Current cloud-init instance-id: $currentInstanceId"
                }

                try {
                    $null = Invoke-VMScript -VM $vm -ScriptText "rm -f $guestQuickPath" -ScriptType Bash `
                        -GuestUser $guestUser -GuestPassword $guestPass -ErrorAction Stop
                    Write-Log "Removed quick-check script from the VM: $guestQuickPath"
                } catch {
                    Write-Verbose "Failed to remove quick-check script from the VM: $_"
                }

                switch ($qcRes.ExitCode) {
                    2 {
                        Write-Log -Error "Quick-check reported TERMINAL (exit code 2). stdout: '$firstLine' stderr: '$qcStderr'"
                        Write-Log -Warn "Phase 3 complete (cloud-init NOT confirmed)."
                        Exit 2
                    }
                    1 {
                        Write-Log -Warn "Quick-check: guest returned NOTRAN (exit code 1). stdout: '$firstLine' stderr: '$qcStderr'"
                        Write-Log -Warn "Phase 3 complete (cloud-init NOT confirmed)."
                        Exit 2
                    }
                    0 {
                        # Success: Use the parsed label to decide action
                        switch ($label) {
                            'RAN-SEM' {
                                Write-Log "Quick-check: success by module sem; evidence: $evidencePath. Proceeding to cloud-init completion polling."
                            }
                            'RAN' {
                                Write-Log "Quick-check: success by cloud-init artifacts; evidence: $evidencePath. Proceeding to cloud-init completion polling."
                            }
                            'RAN-NET' {
                                Write-Log "Quick-check: success by network-config; evidence: $evidencePath. As this is a weak evidence, proceeding to cloud-init completion polling with reduced wait (60s)."
                                $cloudInitWaitTotalSec = [int]([math]::Max(30, [math]::Min($cloudInitWaitTotalSec, 60)))
                            }
                            default {
                                # ExitCode 0 but no recognised token -> fold-down policy (shorten wait and continue polling)
                                Write-Log -Warn "Quick-check: ExitCode 0 but stdout missing expected token (stdout='$firstLine', qcStderr='$qcStderr')"
                                Write-Log -Warn "Proceeding to cloud-init completion check with reduced wait to avoid pointless long polling; operator should investigate."
                                $cloudInitWaitTotalSec = [int]([math]::Max(30, [math]::Min($cloudInitWaitTotalSec, 60)))
                                # fall through to normal polling
                            }
                        }
                    }
                    default {
                        # Unexpected exit code — be conservative
                        Write-Log -Error "Quick-check: unexpected exit code $($qcRes.ExitCode). stdout: '$qcStdout' stderr: '$qcStderr'. Aborting Phase-3."
                        Exit 2
                    }
                }
            }
        }
    }

    #--- The real cloud-init completion check.

    $localCheckPath = Join-Path $workdir "check-cloud-init.sh"
    $guestCheckPath = "$workDirOnVM/check-cloud-init.sh"

    # Template for guest checker. Use {{SEED_TS}} placeholder and replace locally.
    $cloudInitCheckScript = @'
#!/bin/bash
# check-cloud-init.sh - return READY:reason when cloud-init for this seed attach is finished
# Exit codes:
#   0 = READY (success for one of tests)
#   1 = NOTREADY (not finished)
#   2 = TERMINAL (cloud-init disabled or other terminal condition)
if [ -f /etc/cloud/cloud-init.disabled ]; then
  echo "TERMINAL:cloud-init-disabled"
  exit 2
fi
if command -v cloud-init >/dev/null 2>&1; then
  if cloud-init status --wait >/dev/null 2>&1; then
    echo "READY:cloud-init-status"
    exit 0
  fi
fi
if systemctl show -p SubState --value cloud-final 2>/dev/null | grep -q ^exited$; then
  echo "READY:systemd-cloud-final-exited"
  exit 0
fi
if [ -f /var/lib/cloud/instance/boot-finished ]; then
  file_ts=$(stat -c %Y /var/lib/cloud/instance/boot-finished 2>/dev/null || echo 0)
  if [ "$file_ts" -gt {{SEED_TS}} ]; then
    echo "READY:boot-finished-after-seed"
    exit 0
  fi
fi
echo "NOTREADY"
exit 1
'@

    # Replace placeholder with the seed attach epoch
    $cloudInitCheckScript = $cloudInitCheckScript.Replace('{{SEED_TS}}', [string]$seedAttachEpoch)

    # Write local script file
    Set-Content -Path $localCheckPath -Value $cloudInitCheckScript -Encoding UTF8 -Force

    # normalize CRLF -> LF and write as UTF-8 without BOM
    $txt = Get-Content -Raw -Path $localCheckPath -Encoding UTF8
    $txt = $txt -replace "`r`n", "`n"
    $txt = $txt -replace "`r", "`n"
    [System.IO.File]::WriteAllText($localCheckPath, $txt, (New-Object System.Text.UTF8Encoding($false)))

    Write-Verbose "Wrote local check script: $localCheckPath"

    # Copy the local script to the VM with retries (tools may still be flaky)
    $maxAttempts = 4
    $attempt = 0
    $copied = $false

    while (-not $copied -and $attempt -lt $maxAttempts) {
        $attempt++
        try {
            $null = Copy-VMGuestFile -LocalToGuest -Source $localCheckPath -Destination $guestCheckPath `
                -VM $vm -GuestUser $guestUser -GuestPassword $guestPass -Force -ErrorAction Stop
            $copied = $true
            Write-Verbose "Copied script to the VM ($guestCheckPath) (attempt $attempt)"
        } catch {
            Write-Verbose "Copy-VMGuestFile failed (attempt $attempt): $_"
            # try waiting for tools briefly and retry
            $toolsOk2 = Wait-ForVMwareTools -VM $vm -TimeoutSec 30
            if (-not $toolsOk2) {
                Write-Verbose "VMware Tools still unavailable; sleeping before next copy attempt..."
                Start-Sleep -Seconds 10
            } else {
                Write-Verbose "VMware Tools recovered; retrying copy..."
            }
        }
    }

    # cleanup local temp script
    Remove-Item -Path $localCheckPath -ErrorAction SilentlyContinue

    if (-not $copied) {
        Write-Log -Error "Failed to upload check script to the VM after $maxAttempts attempts."
        Exit 2
    }

    try {
        $phase3cmd = @"
sudo /bin/bash -c "chmod +x $guestCheckPath"
"@
        $null = Invoke-VMScript -VM $vm -ScriptText $phase3cmd -ScriptType Bash `
            -GuestUser $guestUser -GuestPassword $guestPass -ErrorAction stop
        Write-Verbose "Set permissions on check script on the VM: $guestCheckPath"
    } catch {
        Write-Log -Error "Failed to set permissions on check script on the VM: $_"
    }

    # Poll the script until it returns READY or timeout
    $cloudInitWaitTotalSec = if ($params.cloudinit_wait_sec) { [int]$params.cloudinit_wait_sec } else { 600 }
    $cloudInitPollSec =      if ($params.cloudinit_poll_sec) { [int]$params.cloudinit_poll_sec } else { 10 }
    $toolsWaitSec = if ($params.cloudinit_tools_wait_sec) { [int]$params.cloudinit_tools_wait_sec } else { 60 }
    $toolsPollSec = if ($params.cloudinit_tools_poll_sec) { [int]$params.cloudinit_tools_poll_sec } else { 10 }
    $elapsed = 0
    $cloudInitDone = $false

    Write-Log "Waiting for cloud-init to finish inside the VM (polling $guestCheckPath, max ${cloudInitWaitTotalSec}s)..."

    while ($elapsed -lt $cloudInitWaitTotalSec) {
        try {
            $execCmd = "sudo /bin/bash '$guestCheckPath'"
            $res = Invoke-VMScript -VM $vm -GuestUser $guestUser -GuestPassword $guestPass `
                -ScriptText $execCmd -ScriptType Bash -ErrorAction Stop

            Write-Verbose ("Invoke-VMScript result: " + ($res | Format-List * | Out-String))

            $stdout = ""
            if ($res.ScriptOutput) {
                $stdout = ($res.ScriptOutput -join "`r`n").Trim()
            }
            elseif ($res.ScriptError) {
                $stdout = ($res.ScriptError -join "`r`n").Trim()
            }
            else {
                $stdout = ""
            }

            if ($res.ExitCode -eq 0) {
                if ($stdout -match '^READY:([^\r\n]+)') { $reason = $matches[1] } else { $reason = 'unknown' }
                Write-Log "Detected cloud-init completion on guest (reason: $reason)."
                $cloudInitDone = $true
                break
            } elseif ($res.ExitCode -eq 2) {
                Write-Log -Warn "Guest reports terminal state: $stdout"
                Write-Log -Warn "Detected terminal cloud-init state on guest (i.e. /etc/cloud/cloud-init.disabled exists)"
                if ($Phase -contains 4) {
                    Write-Log -Error "Continuing into Phase-4 would be meaningless and could produce unpredictable results; aborting the entire script."
                } else {
                    Write-Log -Warn "Phase-3 (seed attach and boot) may have been ineffective."
                }
                Exit 2
            } else {
                # NOTREADY (ExitCode != 0)
                Write-Verbose "cloud-init not yet finished; continue polling..."
            }
        } catch {
            Write-Verbose "Invoke-VMScript execution failed while checking cloud-init: $_"
            Write-Verbose "Waiting up to ${toolsWaitSec}s for VMware Tools to recover (poll interval ${toolsPollSec}s)..."

            $toolsBack = Wait-ForVMwareTools -VM $vm -TimeoutSec $toolsWaitSec -PollIntervalSec $toolsPollSec
            if (-not $toolsBack) {
                Write-Verbose "VMware Tools did not recover within ${toolsWaitSec}s; will retry guest check after the normal poll sleep."
            } else {
                Write-Verbose "VMware Tools recovered; retrying guest check immediately."
            }
        }

        Start-Sleep -Seconds $cloudInitPollSec
        $elapsed += $cloudInitPollSec
    }

    try {
        $null = Invoke-VMScript -VM $vm -ScriptText "rm -f $guestCheckPath" -ScriptType Bash `
            -GuestUser $guestUser -GuestPassword $guestPass -ErrorAction Stop
        Write-Log "Removed check script from the VM: $guestCheckPath"
    } catch {
        Write-Verbose "Failed to remove check script from the VM: $_"
    }

    if (-not $cloudInitDone) {
        Write-Log -Error "cloud-init was triggered at VM startup, but it could not be confirmed whether the VM has completed applying the system changes."
        Write-Log -Error "Timed out waiting for cloud-init to finish after ${cloudInitWaitTotalSec}s."
        if ($Phase -contains 4) {
            Write-Log -Error "Aborting without proceeding to Phase-4 to avoid detaching the seed ISO before cloud-init completion."
        }
        Exit 2
    }

    Write-Log "Phase 3 complete"
}

# ---- Phase 4: Close & Clean up the deployed VM ----
function CloseDeploy {
    Write-Log "=== Phase 4: Close & Clean up ==="

    # 1. Get VM object
    $vm = TryGet-VMObject $new_vm_name
    if (-not $vm) {
        Write-Log -Error "Target VM not found: '$new_vm_name'"
        Exit 1
    }

    # 2. Get datacenter, datastore, and seed ISO path (same logic as Phase 3)
    $seedIsoCopyStore = $params.seed_iso_copy_store.TrimEnd('/').TrimEnd('\')
    $datacenterName = $params.datacenter_name

    if (-not $seedIsoCopyStore) {
        Write-Log -Error "Parameter 'seed_iso_copy_store' is not set. Please check your parameter file."
        Exit 2
    }
    if (-not $datacenterName) {
        Write-Log -Error "Parameter 'datacenter_name' is not set. Please check your parameter file."
        Exit 2
    }

    # Split into datastore name and folder path (same as Phase 3)
    if ($seedIsoCopyStore -match "^\[(.+?)\]\s*(.+)$") {
        $datastoreName = $matches[1]
        $datastoreFolder = $matches[2].Trim('/')
    } else {
        Write-Log -Error "Invalid format for parameter 'seed_iso_copy_store': $seedIsoCopyStore"
        Exit 2
    }

    $vmstoreFolderPath = "vmstore:\$datacenterName\$datastoreName\$datastoreFolder"
    $vmstoreIsoPath = "$vmstoreFolderPath\$seedIsoName"

    # 3. Detach seed ISO from VM's CD drive
    $cdd = Get-CDDrive -VM $vm
    if (-not $cdd) {
        Write-Log -Warn "No CD/DVD drive found on this VM."
    }
    else {
        try {
            $null = Set-CDDrive -CD $cdd -NoMedia -Confirm:$false -ErrorAction Stop
            Write-Log "Seed ISO media is detached from the VM: '$new_vm_name'"
        } catch {
            # Not fatal, continue, as the cmdlet returns true if it is already detached
            Write-Log -Warn "Failed to detach CD/DVD drive from VM: $_"
        }
    }

    # 4. Remove seed ISO file from datastore (use Remove-Item on vmstore: path)
    if (Test-Path "$vmstoreIsoPath") {
        try {
            Remove-Item -Path $vmstoreIsoPath -Force
            Write-Log "Removed seed ISO from datastore: $vmstoreIsoPath"
        } catch {
            Write-Log -Warn "Failed to remove seed ISO '$vmstoreIsoPath' from datastore: $_"
        }
    } else {
        Write-Log "Seed ISO file not found in datastore for removal: $vmstoreIsoPath"
    }

    # 5. Disable cloud-init for future boots (unless -NoCloudReset switch is specified)
    if (-not $NoCloudReset) {
        $toolsOk = Wait-ForVMwareTools -VM $vm -TimeoutSec 30
        if (-not $toolsOk) {
            Write-Log -Error "Unable to disable cloud-init since VMware Tools is NOT running. Make sure the VM is powered on and rerun Phase-4."
            exit 1
        }

        # Prepare username and password for VM commands
        $guestUser = $params.username
        $guestPassPlain = $params.password
        $guestPass = ConvertToSecureStringFromPlain $guestPassPlain
        if (-not $guestPass) {
            Write-Log -Error "Failed to convert guest password to SecureString. Aborting in Phase-4."
            Exit 3
        }

        try {
            $phase4cmd = @'
sudo /bin/bash -c "install -m 644 /dev/null /etc/cloud/cloud-init.disabled"
'@
            $null = Invoke-VMScript -VM $vm -ScriptText $phase4cmd -GuestUser $guestUser `
                -GuestPassword $guestPass -ScriptType Bash -ErrorAction Stop
            Write-Log "Created /etc/cloud/cloud-init.disabled to prevent cloud-init invocation."
        } catch {
            Write-Log -Error "Failed to create cloud-init.disabled file: $_"
        }
    } else {
        Write-Log "Skipped deactivation of cloud-init due to -NoCloudReset switch."
    }

    Write-Log "Phase 4 complete"
}

# ---- Phase dispatcher (add phase 3) ----
foreach ($p in $phaseSorted) {
    switch ($p) {
        1 { AutoClone }
        2 { InitializeClone }
        3 { CloudInitKickStart }
        4 { CloseDeploy }
    }
}

Write-Log "Deployment script completed."
