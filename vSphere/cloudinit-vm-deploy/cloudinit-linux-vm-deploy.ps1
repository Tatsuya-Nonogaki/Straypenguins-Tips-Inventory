<#
.SYNOPSIS
  Automated vSphere Linux VM deployment using cloud-init seed ISO.
.DESCRIPTION
  3-phase deployment: (1) Clone/spec, (2) Guest init, (3) Seed/boot.
  Uses a YAML parameter file (see vm-settings.example.yaml).
.PARAMETER Phase
  List of steps (1,2,3) to execute. e.g. -Phase 1,2,3 or -Phase 2
.PARAMETER Config
  Path to YAML parameter file for VM deployment.
.PARAMETER NoRestart
  If set, disables auto-poweron/shutdown except when multi-phase is needed.
.EXAMPLE
  .\cloudinit-linux-vm-deploy.ps1 -Phase 1,2,3 -Config .\params\vm-settings.yaml
.NOTES
  Requires: PowerCLI, powershell-yaml, vSphere 8+, Windows Server 2019+
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet(1,2,3)]
    [int[]]$Phase,

    [Parameter(Mandatory)]
    [string]$Config,

    [switch]$NoRestart
)

# ---- Globals ----
$vcport = 443
$connRetry = 2
$connRetryInterval = 5
$scriptdir = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$LogFilePath = Join-Path $scriptdir ("deploy-" + (Get-Date -Format 'yyyyMMdd_HHmmss') + ".log")

function Write-Log {
    param ([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -Append -FilePath $LogFilePath -Encoding UTF8
    Write-Host $Message
}

function VIConnect {
    # expects $vcserver, $vcuser, $vcpasswd in scope
    process {
        for ($i = 1; $i -le $connRetry; $i++) {
            try {
                if ([string]::IsNullOrEmpty($vcuser) -or [string]::IsNullOrEmpty($vcpasswd)) {
                    Write-Host "Connect-VIServer $vcserver -Port $vcport -Force"
                    Connect-VIServer $vcserver -Port $vcport -Force -WarningAction SilentlyContinue -ErrorAction Continue -ErrorVariable myErr
                } else {
                    Write-Host "Connect-VIServer $vcserver -Port $vcport -User $vcuser -Password ******** -Force"
                    Connect-VIServer $vcserver -Port $vcport -User $vcuser -Password $vcpasswd -Force -WarningAction SilentlyContinue -ErrorAction Continue -ErrorVariable myErr
                }
                if ($?) { break }
            } catch {
                Write-Log "Failed to connect (attempt $i): $_"
            }
            if ($i -eq $connRetry) {
                Write-Host "Connection attempts exceeded retry limit" -ForegroundColor Red
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
    Exit 2
}
try {
    $params = ConvertFrom-Yaml (Get-Content $Config -Raw)
} catch {
    Write-Host "Failed to parse YAML: $Config" -ForegroundColor Red
    Exit 3
}

# ---- vCenter connection variables ----
$vcserver = $params.vcenter_host
$vcuser   = $params.vcenter_user
$vcpasswd = $params.vcenter_password

# ---- Connect to vCenter ----
VIConnect

# ---- Phase 1: Clone & Spec ----
function Phase1-CloneAndSpec {
    Write-Log "=== Phase 1: Clone & Spec ==="
    $templateVM = Get-VM -Name $params.template_vm_name -ErrorAction Stop

    # Clone VM
    $newVM = New-VM -Name $params.new_vm_name `
        -VM $templateVM `
        -ResourcePool (Get-Cluster -Name $params.cluster_name | Get-ResourcePool | Select-Object -First 1) `
        -Datastore $params.datastore_name `
        -VMHost $params.esxi_host `
        -NetworkName $params.network_label `
        -ErrorAction Stop

    Write-Log "Cloned new VM: $($newVM.Name)"

    # Set CPU/memory
    Set-VM -VM $newVM -NumCpu $params.cpu -MemoryMB $params.memory_mb -Confirm:$false -ErrorAction Stop
    Write-Log "Set CPU: $($params.cpu), Mem: $($params.memory_mb) MB"

    # Adjust disks
    foreach ($d in $params.disks) {
        $disk = Get-HardDisk -VM $newVM | Where-Object { $_.Name -like "*$($d.device)*" }
        if ($disk -and $disk.CapacityGB -lt $d.size_gb) {
            Set-HardDisk -HardDisk $disk -CapacityGB $d.size_gb -Confirm:$false
            Write-Log "Resized disk $($d.device) to $($d.size_gb) GB"
        }
    }

    # (Optional) Adjust/add NICs here as needed

    # Do not power on (Phase 2/3 will handle)
    Write-Log "Phase 1 complete"
}

# ---- Phase dispatcher ----
foreach ($p in $Phase | Sort-Object) {
    switch ($p) {
        1 { Phase1-CloneAndSpec }
        # 2 { Phase2-GuestInit }
        # 3 { Phase3-SeedAndBoot }
    }
}

Write-Log "Deployment script completed."
