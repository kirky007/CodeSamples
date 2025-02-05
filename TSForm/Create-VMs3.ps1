# Convert JSON to PowerShell objects
$servers = $jsonInput | ConvertFrom-Json

# Paths to your WIM file and unattend file
$wimPath = "C:\path\to\install.wim"
$unattendPath = "C:\path\to\unattend.xml"

# Function to create VM and apply WIM with unattend.xml
function Create-VMAndApplyWIM {
    param (
        [string]$VMName,
        [string]$Memory,
        [string]$VHDSize,
        [int]$VCPUs,
        [string]$SwitchName,
        [string]$Role
    )

    # Create VM
    New-VM -Name $VMName -MemoryStartupBytes $Memory -VHDPath "$($env:USERPROFILE)\VMs\$VMName.vhdx" -SwitchName $SwitchName -Generation 2
    Set-VMProcessor -VMName $VMName -Count $VCPUs
    Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $true

    # Create VHD if not already created
    $vhdPath = "$($env:USERPROFILE)\VMs\$VMName.vhdx"
    if (-not (Test-Path $vhdPath)) {
        New-VHD -Path $vhdPath -SizeBytes $VHDSize -Dynamic
    }

    # Apply WIM to VHD (Assuming you have the necessary tools like DISM)
    Mount-VHD -Path $vhdPath
    $disk = Get-Disk | Where-Object { $_.Location -eq $vhdPath }
    $partition = $disk | Get-Partition | Where-Object { $_.Type -eq "Basic" -and $_.DriveLetter -eq $null }
    if ($partition) {
        $partition | Set-Partition -NewDriveLetter 'Z'
        try {
            DISM /Apply-Image /ImageFile:$wimPath /Index:1 /ApplyDir:Z:\
            DISM /Apply-Unattend:$unattendPath /Image:Z:\
        } finally {
            Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $partition.PartitionNumber -AccessPath "Z:"
        }
    }
    Dismount-VHD -Path $vhdPath

    Write-Host "VM '$VMName' created with role '$Role'."
}

# Process each server configuration
foreach ($server in $servers) {
    # Here we're assuming 'COR' for site type to keep the script simple. In a real scenario, you'd 
    # dynamically choose based on actual site type.
    if ("COR" -in $server.SiteType) {
        Create-VMAndApplyWIM -VMName $server.Name -Memory $server.Memory -VHDSize $server.VHDSize -VCPUs $server.VCPUs -SwitchName $server.SwitchName -Role $server.Role
    }
}

Write-Host "All VMs have been processed."
