<#
.SYNOPSIS
  Automated vSphere Linux VM deployment using cloud-init seed ISO.
  Version: 0.0.7

.DESCRIPTION
  3-phase deployment: (1) Automatic Cloning, (2) Clone Initialization, (3) Kick Cloud-init Start.
  Uses a YAML parameter file (see vm-settings.example.yaml).

.PARAMETER Phase
  (Alias -p) List of steps (1,2,3) to execute. e.g. -Phase 1,2,3 or -Phase 2

.PARAMETER Config
  (Alias -c) Path to YAML parameter file for VM deployment.

.PARAMETER NoRestart
  If set, disables auto-poweron/shutdown except when multi-phase is needed.

.EXAMPLE
  .\cloudinit-linux-vm-deploy.ps1 -Phase 1,2,3 -Config .\params\vm-settings.yaml

.NOTES
  Requires: PowerCLI, powershell-yaml, vSphere 8+, Windows Server 2019+
  Exit codes:
    0: Success
    1: General runtime error (VM operations, PowerCLI, etc)
    2: System/environment/file error (directory/file creation, etc)
    3: Bad arguments or parameter/config input
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

$scriptdir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$spooldir = Join-Path $scriptdir "spool"

if (-not (Test-Path $spooldir)) {
    Write-Host "Error: $spooldir does not exist. Please create it before running this script." -ForegroundColor Red
    Exit 2
}

if (-Not (Get-Module VMware.VimAutomation.Core)) {
    Write-Host "Loading vSphere PowerCLI. This may take a while..."
    Import-Module VMware.VimAutomation.Core -ErrorAction SilentlyContinue
}

# ---- Phase argument check ----
$phaseSorted = $Phase | Sort-Object
for ($i=1; $i -lt $phaseSorted.Count; $i++) {
    if ($phaseSorted[$i] -ne $phaseSorted[$i-1] + 1) {
        Write-Host "Error: Invalid -Phase sequence (missing phase between $($phaseSorted[$i-1]) and $($phaseSorted[$i]))." -ForegroundColor Red
        Exit 3
    }
}

# ---- NoRestart一元管理 ----
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


# ---- LogFilePath (temporary) ----
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
    # expects $vcserver, $vcuser, $vcpasswd in scope
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
    param([Parameter(Mandatory)][object]$VM)
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
Import-Module powershell-yaml -ErrorAction Stop
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

# ---- Resolve working directory ----
$new_vm_name = $params.new_vm_name
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

# ---- vCenter connection variables ----
$vcport = 443
$connRetry = 2
$connRetryInterval = 5
$vcserver = $params.vcenter_host
$vcuser   = $params.vcenter_user
$vcpasswd = $params.vcenter_password

# ---- Connect to vCenter ----
VIConnect

# ---- Clone Template VM to the target VM with specified spec ----
function AutoClone {
    Write-Log "=== Phase 1: Automatic Cloning ==="

    # Clone
    try {
        $templateVM = Get-VM -Name $params.template_vm_name -ErrorAction Stop

        if ([string]::IsNullOrEmpty($params.resource_pool_name) -or $params.resource_pool_name -eq "Resources") {
            $resourcePool = (Get-Cluster -Name $params.cluster_name | Get-ResourcePool | Where-Object { $_.Name -eq "Resources" })
        } else {
            $resourcePool = (Get-Cluster -Name $params.cluster_name | Get-ResourcePool | Where-Object { $_.Name -eq $params.resource_pool_name })
            if (-not $resourcePool) {
                Write-Log -Error "Specified Resource Pool not found: $($params.resource_pool_name)"
                Exit 3
            }
        }

        $newVM = New-VM -Name $params.new_vm_name `
            -VM $templateVM `
            -ResourcePool $resourcePool `
            -Datastore $params.datastore_name `
            -VMHost $params.esxi_host `
            -NetworkName $params.network_label `
            -ErrorAction Stop
        Write-Log "Cloned new VM: $($newVM.Name) in $($params.datastore_name)"
    } catch {
        Write-Log -Error "Error occurred during VM clone: $_"
        Exit 1
    }

    # CPU/mem
    try {
        Set-VM -VM $newVM -NumCpu $params.cpu -MemoryMB $params.memory_mb -Confirm:$false -ErrorAction Stop
        Write-Log "Set CPU: $($params.cpu), Mem: $($params.memory_mb) MB"
    } catch {
        Write-Log -Error "Error during CPU/memory set: $_"
        Exit 1
    }

    # Disks
    foreach ($d in $params.disks) {
        try {
            $disk = Get-HardDisk -VM $newVM | Where-Object { $_.Name -like "*$($d.device)*" }
            if ($disk -and $disk.CapacityGB -lt $d.size_gb) {
                Set-HardDisk -HardDisk $disk -CapacityGB $d.size_gb -Confirm:$false
                Write-Log "Resized disk $($d.device) to $($d.size_gb) GB"
            }
        } catch {
            Write-Log -Error "Error resizing disk $($d.device): $_"
            Exit 1
        }
    }

    Write-Log "Phase 1 complete"
}

function InitializeClone {
    Write-Log "=== Phase 2: Guest Initialization ==="

    # VM取得
    try {
        $vm = Get-VM -Name $params.new_vm_name -ErrorAction Stop
    } catch {
        Write-Log -Error "VM not found for initialization: $($params.new_vm_name)"
        Exit 1
    }

    # ゲスト認証情報（SecureString化）
    $guestUser = $params.username
    $guestPassPlain = $params.password
    try {
        $guestPass = $guestPassPlain | ConvertTo-SecureString -AsPlainText -Force
    } catch {
        Write-Log -Error "Failed to convert guest password to SecureString: $_"
        Exit 3
    }

    # スクリプトファイル存在チェック
    $scriptSrc = Join-Path $scriptdir "scripts/init-vm-cloudinit.sh"
    if (-not (Test-Path $scriptSrc)) {
        Write-Log -Error "Required script not found: $scriptSrc"
        Exit 2
    }

    # VM起動（Start-MyVMを利用）
    Start-MyVM $vm

    # VMware Tools待ち
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

    # スクリプトをゲストOSにコピー
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

    # スクリプト実行
    try {
        $result = Invoke-VMScript -VM $vm -ScriptText "chmod +x $dstPath && sudo $dstPath" `
            -GuestUser $guestUser -GuestPassword $guestPass `
            -ErrorAction Stop
        Write-Log "Executed init script in guest. Output: $($result.ScriptOutput)"
    } catch {
        Write-Log -Error "Failed to execute script in guest: $_"
        Exit 1
    }

    # スクリプト削除
    try {
        $result = Invoke-VMScript -VM $vm -ScriptText "rm -f $dstPath" `
            -GuestUser $guestUser -GuestPassword $guestPass `
            -ErrorAction Stop
        Write-Log "Removed init script from guest: $dstPath"
    } catch {
        Write-Log -Warn "Failed to remove script from guest: $_"
    }

    # VM停止
    Stop-MyVM $vm

    Write-Log "Phase 2 complete"
}

# ---- Phase dispatcher ----
foreach ($p in $phaseSorted) {
    switch ($p) {
        1 { AutoClone }
        2 { InitializeClone }
        # 3 { CloudInitKickStart }
    }
}

Write-Log "Deployment script completed."
