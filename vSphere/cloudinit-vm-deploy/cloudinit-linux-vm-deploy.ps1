<#
.SYNOPSIS
  Automated vSphere Linux VM deployment using cloud-init seed ISO.
  Version: 0.0.17

.DESCRIPTION
  Automate deployment of a Linux VM from template VM, leveraging cloud-init, in 3 phases:
  (1) Automatic Cloning, (2) Clone Initialization, (3) Kick Cloud-init Start
  Uses a YAML parameter file (see vm-settings_example.yaml).
  
  **Requirements:**
  * vSphere virtual machine environment (8+ recommended)
  * VMware PowerCLI
  * powershell-yaml module
  * mkisofs: ISO builder command; Redefine the variable in "Global variables"
    section if you want to use an alternative (with appropriate option flags).
  
  **Exit codes:**
    0: Success
    1: General runtime error (VM operations, PowerCLI, etc)
    2: System/environment/file error (directory/file creation, etc)
    3: Bad arguments or parameter/config input

.PARAMETER Phase
  (Alias -p) List of steps (1,2,3) to execute. e.g. -Phase 1,2,3 or -Phase 2

.PARAMETER Config
  (Alias -c) Path to YAML parameter file for the VM deployment.

.PARAMETER NoRestart
  If set, disables auto-poweron/shutdown except when multi-phase is needed.

.EXAMPLE
  .\cloudinit-linux-vm-deploy.ps1 -Phase 1,2,3 -Config .\params\vm-settings.yaml
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(1,2,3)]
    [Alias("p")]
    [int[]]$Phase,

    [Parameter(Mandatory)]
    [Alias("c")]
    [string]$Config,

    [switch]$NoRestart
)

#
# ---- Global variables ----
#
$scriptdir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$spooldir = Join-Path $scriptdir "spool"

$mkisofs = "C:\work\cdrtfe\tools\cdrtools\mkisofs.exe"

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
        [switch]$Force
    )
    if ($Force -or -not $NoRestart) {
        if ($VM.PowerState -ne "PoweredOn") {
            try {
                Start-VM -VM $VM -ErrorAction Stop | Out-Null
                Write-Log "Started VM: $($VM.Name)"
            } catch {
                Write-Log -Error "Failed to start VM: $_"
                Exit 1
            }
        } else {
            Write-Log "VM already powered on: $($VM.Name)"
        }
    } else {
        Write-Log "NoRestart specified: VM remains powered off."
    }
}

function Stop-MyVM {
    param([Parameter(Mandatory)][object]$VM)
    if (-not $NoRestart) {
        try {
            Stop-VM -VM $VM -Confirm:$false -ErrorAction Stop
            Write-Log "Stopped VM: $($VM.Name)"
        } catch {
            Write-Log -Warn "Failed to stop VM: $_"
        }
    } else {
        Write-Log "NoRestart specified: VM remains powered on."
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
        $vmParams['NetworkName'] = $params.network_name
    }

    try {
        $newVM = New-VM @vmParams | Tee-Object -Variable newVMOut | Out-File $LogFilePath -Append -Encoding UTF8
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
                        Write-Log "Resized disk $($disk.Name) to $($d['size_gb']) GB"
                    } catch {
                        Write-Log -Error "Error resizing disk $($d['name']): $_"
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
        $guestPass = $guestPassPlain | ConvertTo-SecureString -AsPlainText -Force
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
            $resp = Read-Host "Start VM anyway? [Y]/n (If you answer N, the entire script will abort here.)"
            if ($resp -eq "" -or $resp -eq "Y" -or $resp -eq "y") {
                Start-MyVM $vm -Force
            } else {
                Write-Log -Error "User aborted due to NoRestart restriction."
                Exit 1
            }
        } else {
            # No prompt; delegate further processing and messaging to Start-MyVM
            Start-MyVM $vm -Force
        }
    } else {
        Start-MyVM $vm
    }

    # Wait until the VM starts
    try {
        $timeoutSec = 120
        $waited = 0
        while ($vm.ExtensionData.Guest.ToolsStatus -ne "toolsOk" -and $waited -lt $timeoutSec) {
            Start-Sleep -Seconds 5
            $waited += 5
            $vm = Get-VM -Name $params.new_vm_name
        }
        if ($vm.ExtensionData.Guest.ToolsStatus -ne "toolsOk") {
            Write-Log -Error "VMware Tools not ready in VM after $timeoutSec seconds."
            Exit 1
        }
        Write-Log "VMware Tools is running in guest."
    } catch {
        Write-Log -Warn "Error waiting for VMware Tools: $_"
    }

    # Transfer the script and run on the clone
    try {
        $dstPath = "/tmp/init-vm-cloudinit.sh"
        Copy-VMGuestFile -Source $scriptSrc -Destination $dstPath `
            -VM $vm -GuestUser $guestUser -GuestPassword $guestPass `
            -Force -ErrorAction Stop
        Write-Log "Copied init script to guest: $dstPath"
    } catch {
        Write-Log -Error "Failed to copy script to guest: $_"
        Exit 1
    }

    try {
        $result = Invoke-VMScript -VM $vm -ScriptText "chmod +x $dstPath && sudo $dstPath" `
            -GuestUser $guestUser -GuestPassword $guestPass `
            -ErrorAction Stop
        Write-Log "Executed init script in guest. Output: $($result.ScriptOutput)"
    } catch {
        Write-Log -Error "Failed to execute script in guest: $_"
        Exit 1
    }

    try {
        $result = Invoke-VMScript -VM $vm -ScriptText "rm -f $dstPath" `
            -GuestUser $guestUser -GuestPassword $guestPass `
            -ErrorAction Stop
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
            Remove-Item -Recurse -Force $seedDir
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

    foreach ($f in $seedFiles) {
        $tplPath = Join-Path $tplDir $f.tpl
        if (-not (Test-Path $tplPath)) {
            Write-Log -Error "Missing template: $tplPath"
            Exit 2
        }
        try {
            $template = Get-Content $tplPath -Raw
            # Replace: {{KEY}} -> $params.KEY
            $output = $template
            foreach ($k in $params.PSObject.Properties.Name) {
                $output = $output -replace "{{\s*$k\s*}}", [string]$params.$k
            }
            $seedOut = Join-Path $seedDir $f.out
            $output | Set-Content -Encoding UTF8 $seedOut
            Write-Log "Generated $($f.out) for cloud-init"
        } catch {
            Write-Log -Error "Failed to render $($f.tpl): $_"
            Exit 2
        }
    }

    # 4. Create seed ISO with mkisofs
    if (-not (Test-Path $mkisofs)) {
        Write-Log -Error "ISO building tool not found: $mkisofs"
        Exit 2
    }
    $isoPath = Join-Path $workdir "seed.iso"
    $cmd = "`"$mkisofs`" -output `"$isoPath`" -V cidata -r -J `"$seedDir`""
    Write-Log "Running: $cmd"
    $mkisofsOut = cmd /c $cmd 2>&1
    if (-not (Test-Path $isoPath)) {
        Write-Log -Error "seed.iso not generated: $mkisofsOut"
        Exit 2
    } else {
        Write-Log "cloud-init seed ISO created: $isoPath"
    }

    # 5. Attach ISO to VM's CD drive (add if not present)
    $cd = Get-CDDrive -VM $vm
    if (-not $cd) {
        try {
            $cd = New-CDDrive -VM $vm -ISOPath $isoPath -StartConnected -Confirm:$false
            Write-Log "Added CD drive & attached seed ISO to VM"
        } catch {
            Write-Log -Error "Failed to add/attach CD drive: $_"
            Exit 1
        }
    } else {
        try {
            Set-CDDrive -CDDrive $cd -ISOPath $isoPath -StartConnected $true -Confirm:$false
            Write-Log "Set existing CD drive to attach seed ISO"
        } catch {
            Write-Log -Error "Failed to set CD drive ISO: $_"
            Exit 1
        }
    }

    # 6. Power on VM for personalization
    Start-MyVM $vm

    Write-Log "Phase 3 complete"
}

# ---- Phase dispatcher (add phase 3) ----
foreach ($p in $phaseSorted) {
    switch ($p) {
        1 { AutoClone }
        2 { InitializeClone }
        3 { CloudInitKickStart }
    }
}

Write-Log "Deployment script completed."
