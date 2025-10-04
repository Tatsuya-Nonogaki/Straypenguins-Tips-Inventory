<#
.SYNOPSIS
  Automated vSphere Linux VM deployment using cloud-init seed ISO.
  Version: 0.0.3

.DESCRIPTION
  3-phase deployment: (1) Clone/spec, (2) Guest init, (3) Seed/boot.
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
    Write-Log "=== Phase 1: Automatic Clone ==="

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

# ---- Phase dispatcher ----
foreach ($p in $phaseSorted) {
    switch ($p) {
        1 { AutoClone }
        # 2 { InitializeClone }
        # 3 { KickCloudInitStart }
    }
}

Write-Log "Deployment script completed."
