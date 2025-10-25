<#
.SYNOPSIS
  Automated vSphere Linux VM deployment using cloud-init seed ISO.
  Version: 0.0.3536

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

# ---- VM Power On/Off Functions ----
function Start-MyVM {
    param(
        [Parameter(Mandatory)][object]$VM,
        [switch]$Force,
        [int]$WaitToolsSec = 120
    )
    if ($Force -or -not $NoRestart) {
        if ($VM.PowerState -ne "PoweredOn") {
            try {
                $outNull = Start-VM -VM $VM -ErrorAction Stop | Out-Null
                Write-Log "Started VM: $($VM.Name)"
            } catch {
                Write-Log -Error "Failed to start VM: $_"
                return "start-failed"
            }
        } else {
            Write-Log "VM already powered on: $($VM.Name)"
        }

        $toolsOk = Wait-ForVMwareTools -VM $VM -TimeoutSec $WaitToolsSec
        if ($toolsOk) {
            return "success"
        } else {
            return "timeout"
        }
    } else {
        Write-Log "NoRestart specified: VM remains powered off."
        return "skipped"
    }
}

function Stop-MyVM {
    param(
        [Parameter(Mandatory)][object]$VM,
        [int]$TimeoutSeconds = 180
    )

    $vmName = $VM.Name

    if ($NoRestart) {
       Write-Log "NoRestart specified: VM remains powered on."
       return "skipped"
    }

    $vmObj = $VM

    # Refresh current state
    try {
        $vmObj = Get-VM -Id $vmObj.Id -ErrorAction Stop
    } catch {
        Write-Log -Error "Stop-MyVM: failed to refresh VM object for '$vmName': $_"
        return "stop-failed"
    }

    if ($vmObj.PowerState -eq "PoweredOff") {
        Write-Log "VM already powered off: $vmName"
        return "success"
    }

    Write-Log "Shutting down VM: $vmName"
    try {
        $null = Stop-VM -VM $vmObj -Confirm:$false -ErrorAction Stop
    } catch {
        Write-Log -Warn "Failed to stop VM '$vmName': $_"
        return "stop-failed"
    }

    # Wait for powered off
    $elapsed = 0
    $interval = 5
    while ($elapsed -lt $TimeoutSeconds) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        try {
            $vmObj = Get-VM -Id $vmObj.Id -ErrorAction Stop
        } catch {
            Write-Log -Warn "Stop-MyVM: cannot refresh VM object for '$vmName' while waiting: $_"
            return "stop-failed"
        }
        if ($vmObj.PowerState -eq "PoweredOff") {
            Write-Log "VM is now powered off: $vmName"
            return "success"
        }
        Write-Host "Waiting for VM '$vmName' to power off... ($elapsed/$TimeoutSeconds s)"
    }

    Write-Log -Error "Timeout waiting for VM '$vmName' to reach PoweredOff after $TimeoutSeconds seconds."
    return "timeout"
}

# Wait for VMware Tools to become ready inside the guest
function Wait-ForVMwareTools {
    param(
        [Parameter(Mandatory)][object]$VM,
        [int]$TimeoutSec = 120,
        [int]$PollIntervalSec = 5
    )

    # refresh VM object
    try {
        $vm = Get-VM -Name $VM.Name -ErrorAction Stop
    } catch {
        Write-Log -Warn "Wait-ForVMwareTools: cannot refresh VM object: $_"
        return $false
    }

    $waited = 0
    while ($vm.ExtensionData.Guest.ToolsStatus -ne "toolsOk" -and $waited -lt $TimeoutSec) {
        Start-Sleep -Seconds $PollIntervalSec
        $waited += $PollIntervalSec
        try { $vm = Get-VM -Name $vm.Name -ErrorAction Stop } catch {}
    }

    if ($vm.ExtensionData.Guest.ToolsStatus -eq "toolsOk") {
        Write-Log "VMware Tools is running on VM: $($vm.Name) (waited ${waited}s)."
        return $true
    } else {
        Write-Log -Warn "Timed out waiting for VMware Tools on VM: $($vm.Name) after ${TimeoutSec}s."
        return $false
    }
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
    $existingVM = Get-VM -Name $params.new_vm_name -ErrorAction SilentlyContinue
    if ($existingVM) {
        Write-Log -Error "A VM with the same name '$($params.new_vm_name)' already exists. Aborting deployment."
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
        Name         = $params.new_vm_name
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
        Write-Log "Deployed new VM: $($newVM.Name) from template: $($newVM.Name) in $($params.datastore_name)"
    } catch {
        Write-Log -Error "Error occurred while deploying VM: $($params.new_vm_name): $_"
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

    try {
        $vm = Get-VM -Name $params.new_vm_name -ErrorAction Stop
    } catch {
        Write-Log -Error "VM not found for initialization: $($params.new_vm_name)"
        Exit 1
    }

    $guestUser = $params.username
    $guestPassPlain = $params.password
    try {
        $guestPass = $guestPassPlain | ConvertTo-SecureString -AsPlainText -Force -ErrorAction Stop
    } catch {
        Write-Log -Error "Failed to convert guest password to SecureString: $_"
        Exit 3
    }

    # Prepare the initialization script
    $scriptSrc = Join-Path $scriptdir "scripts/init-vm-cloudinit.sh"
    if (-not (Test-Path $scriptSrc)) {
        Write-Log -Error "Required script not found: $scriptSrc"
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

    switch ($vmStartStatus) {
        "success" {
            Write-Log "VM powered on and VMware Tools is ready for initialization."
        }
        "timeout" {
            Write-Log -Warn "VMware Tools did not become ready after waiting. Guest operations may fail."
        }
        "skipped" {
            Write-Log "VM was not started due to -NoRestart option. Checking current VM state and VMware Tools status..."

            $vm = Get-VM -Name $vm.Name -ErrorAction SilentlyContinue
            Write-Log "VM power state: $($vm.PowerState)"
            $toolsOk = $false
            $toolsOk = Wait-ForVMwareTools -VM $vm -TimeoutSec 5
            if ($toolsOk) {
                Write-Log "VMware Tools is running."
            } else {
                Write-Log "VMware Tools is NOT running."
            }
        }
        "start-failed" {
            Write-Log -Warn "VM could not be started. Initialization aborted."
        }
        default {
            Write-Log -Warn "VM start status is unknown: `"$vmStartStatus`""
        }
    }

    if ($vmStartStatus -ne "success") {
        if (-not ($vmStartStatus -eq "skipped" -and $toolsOk)) {
            Write-Log -Error "Script aborted since VM is not ready for online activities."
            Exit 1
        }
    }

    # Transfer the script and run on the clone
    $dstPath = "$workDirOnVM/init-vm-cloudinit.sh"
    try {
        $phase2Cmd = @"
sudo /bin/bash -c "mkdir -p $workDirOnVM"
"@
        $result = Invoke-VMScript -VM $vm -ScriptText $phase2Cmd -GuestUser $guestUser -GuestPassword $guestPass `
            -ScriptType Bash -ErrorAction Stop
        $phase2Cmd = @"
sudo /bin/bash -c "chown $guestUser $workDirOnVM"
"@
        $result = Invoke-VMScript -VM $vm -ScriptText $phase2Cmd -GuestUser $guestUser -GuestPassword $guestPass `
            -ScriptType Bash -ErrorAction Stop
         Write-Log "Ensured work directory exists on guest: $workDirOnVM"
    } catch {
        Write-Log -Error "Failed to create work directory on guest: $_"
        Exit 1
    }

    try {
        $outNull = Copy-VMGuestFile -LocalToGuest -Source $scriptSrc -Destination $dstPath `
            -VM $vm -GuestUser $guestUser -GuestPassword $guestPass -Force -ErrorAction Stop
        Write-Log "Copied init script to guest: $dstPath"
    } catch {
        Write-Log -Error "Failed to copy script to guest: $_"
        Exit 1
    }

    try {
        $result = Invoke-VMScript -VM $vm -ScriptText "chmod +x $dstPath && sudo /bin/bash $dstPath" `
            -GuestUser $guestUser -GuestPassword $guestPass -ScriptType Bash -ErrorAction Stop
        Write-Log "Executed init script in guest. Output: $($result.ScriptOutput)"
    } catch {
        Write-Log -Error "Failed to execute script in guest: $_"
        Exit 1
    }

    try {
        $result = Invoke-VMScript -VM $vm -ScriptText "rm -f $dstPath" `
            -GuestUser $guestUser -GuestPassword $guestPass -ScriptType Bash -ErrorAction Stop
        Write-Log "Removed init script from guest: $dstPath"
    } catch {
        # Warn but not abort processing if deletion failed
        Write-Log -Warn "Failed to remove script from guest: $_"
    }

    # Shutdown the VM (skipped automatically if applicable)
    Stop-MyVM $vm

    Write-Log "Phase 2 complete"
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

    # 1. Get target VM object
    try {
        $vm = Get-VM -Name $params.new_vm_name -ErrorAction Stop
    } catch {
        Write-Log -Error "Target VM not found: $($params.new_vm_name)"
        Exit 1
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
        $outNull = Copy-DatastoreItem -Item "$isoPath" -Destination "$vmstoreIsoPath" -ErrorAction Stop
        Write-Log "Seed ISO uploaded to datastore: '$vmstoreIsoPath' ($datastoreIsoPath)"
    } catch {
        Write-Log -Error "Failed to upload seed ISO to datastore: $_"
        Exit 2
    }

    # Attach ISO to the VM's CD drive
    try {
        $outNull = Set-CDDrive -CD $cdd -IsoPath "$datastoreIsoPath" -StartConnected $true -Confirm:$false -ErrorAction Stop |
          Tee-Object -Variable setCDOut
          $setCDOut | Select-Object IsoPath,Parent,ConnectionState | Format-List | Out-File $LogFilePath -Append -Encoding UTF8
        Write-Log "Seed ISO attached to the VM's CD drive."
    } catch {
        Write-Log -Error "Failed to attach the seed ISO to the VM's CD drive: $_"
        try {
            $outNull = Remove-DatastoreItem -Path $vmstoreIsoPath -Confirm:$false -ErrorAction Stop
            Write-Log "Cleaned up the uploaded seed ISO from datastore: '$vmstoreIsoPath'"
        } catch {
            Write-Log -Error "Failed to clean up ISO from datastore after attach failure: $_"
        }
        Exit 1
    }

    # 6. Power on VM for personalization
    $vmStartStatus = Start-MyVM $vm

    Write-Log "Phase 3 complete"

    switch ($vmStartStatus) {
        "success" {
            Write-Log "VM powered on and VMware Tools is ready."
        }
        "timeout" {
            Write-Log -Warn "But VMware Tools did not become ready after waiting."
        }
        "skipped" {
            Write-Log "VM was not started due to -NoRestart option. Checking current VM state and VMware Tools status..."

            $vm = Get-VM -Name $vm.Name -ErrorAction SilentlyContinue
            Write-Log "VM power state: $($vm.PowerState)"
            $toolsOk = $false
            $toolsOk = Wait-ForVMwareTools -VM $vm -TimeoutSec 5
            if ($toolsOk) {
                Write-Log "VMware Tools is running."
            } else {
                Write-Log "VMware Tools is NOT running."
            }
        }
        "start-failed" {
            Write-Log -Warn "But VM could not be started."
        }
        default {
            Write-Log -Warn "VM start status is unknown: `"$vmStartStatus`""
        }
    }

    if ($vmStartStatus -ne "success" -and $Phase -contains 4 -and -not $NoCloudReset) {
        Write-Log -Error "Script aborted since VM is not ready for the online activities in Phase 4."
        Exit 2
    }
}

# ---- Phase 4: Close & Clean up the deployed VM ----
function CloseDeploy {
    Write-Log "=== Phase 4: Close & Clean up ==="

    # 1. Get VM object
    try {
        $vm = Get-VM -Name $params.new_vm_name -ErrorAction Stop
    } catch {
        Write-Log -Error "Target VM not found for CloseDeploy: $($params.new_vm_name)"
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
            $outNull = Set-CDDrive -CD $cdd -NoMedia -Confirm:$false -ErrorAction Stop
            Write-Log "Seed ISO media is detached from the VM: $($vm.Name)"
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
        $toolsOk = Wait-ForVMwareTools -VM $vm -TimeoutSec 5
        if ($toolsOk) {
            Write-Log "VMware Tools is running."
        } else {
            Write-Log -Error "Unable to disable cloud-init since VMware Tools is NOT running. Make sure the VM is powered on."
            exit 1
        }

        $guestUser = $params.username
        $guestPassPlain = $params.password
        try {
            $guestPass = $guestPassPlain | ConvertTo-SecureString -AsPlainText -Force -ErrorAction Stop
        } catch {
            Write-Log -Error "Failed to convert guest password to SecureString: $_"
            Exit 3
        }
        try {
            $phase4Cmd = @'
sudo /bin/bash -c "install -m 644 /dev/null /etc/cloud/cloud-init.disabled"
'@
            $result = Invoke-VMScript -VM $vm -ScriptText $phase4Cmd -GuestUser $guestUser `
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
