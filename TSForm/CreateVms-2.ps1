# Helper function to convert GB to bytes
function Convert-GBToBytes {
    param (
        [Parameter(Mandatory=$true)]
        [string]$GBString
    )
    $gbValue = $GBString -replace '[^0-9.]', '' # Remove non-numeric characters, keep only numbers and dot
    [int64]([double]$gbValue * 1GB) # Convert GB to bytes; 1GB = 1,073,741,824 bytes
}

# Function to create a sysprepped VHDX from install.wim
function New-SyspreppedVHDX {
    param (
        [Parameter(Mandatory=$true)]
        [string]$WimPath,
        [Parameter(Mandatory=$true)]
        [string]$VHDXPath,
        [Parameter(Mandatory=$true)]
        [string]$Size,
        [Parameter(Mandatory=$true)]
        [string]$Index
    )

    $sizeInBytes = Convert-GBToBytes -GBString $Size

    # Create a new VHDX
    Write-Host "Creating VHDX at $VHDXPath with size $Size"
    New-VHD -Path $VHDXPath -SizeBytes $sizeInBytes -Dynamic -Confirm:$false

    # Mount the VHDX
    $disk = Mount-VHD -Path $VHDXPath -Passthru
    $volume = $disk | Get-Disk | Get-Partition | Get-Volume
    
    # Initialize disk and create partition
    $disk | Initialize-Disk -PartitionStyle MBR -PassThru | 
    New-Partition -UseMaximumSize -AssignDriveLetter | 
    Format-Volume -FileSystem NTFS -Force -Confirm:$false

    # Apply the WIM to the VHDX
    Write-Host "Applying WIM to VHDX"
    dism /Apply-Image /ImageFile:$WimPath /Index:$Index /ApplyDir:$($volume.DriveLetter + ":\")

    # Copy answer file for sysprep
    $unattendPath = Join-Path $PSScriptRoot "unattend.xml"
    if (Test-Path -Path $unattendPath) {
        Copy-Item -Path $unattendPath -Destination "$($volume.DriveLetter):\Windows\System32\sysprep\unattend.xml" -Force
    } else {
        Write-Warning "Unattend.xml not found. Sysprep might not run automatically."
    }

    # Dismount the VHDX
    Dismount-VHD -Path $VHDXPath

    # Run sysprep on the VHDX
    Write-Host "Preparing to sysprep the VHDX"
    $vhdMount = Mount-VHD -Path $VHDXPath -Passthru
    $vhdVolume = $vhdMount | Get-Disk | Get-Partition | Get-Volume
    $sysprepPath = "$($vhdVolume.DriveLetter):\Windows\System32\sysprep\sysprep.exe"
    if (Test-Path -Path $sysprepPath) {
        Start-Process -FilePath $sysprepPath -ArgumentList "/generalize /oobe /shutdown /unattend:unattend.xml" -Wait -NoNewWindow
    } else {
        Write-Warning "Sysprep.exe not found. Manual sysprep might be required."
    }
    Dismount-VHD -Path $VHDXPath
}

# Define a function to create VM shell
function New-VMShell {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [Parameter(Mandatory=$true)]
        [string]$MemoryStartupBytes,
        [Parameter(Mandatory=$true)]
        [string]$VHDPath,
        [Parameter(Mandatory=$true)]
        [string]$SwitchName
    )

    # Check if VM already exists
    if (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
        Write-Host "VM $Name already exists. Skipping creation."
        return
    }

    # Convert memory from GB string to bytes
    $memoryInBytes = Convert-GBToBytes -GBString $MemoryStartupBytes

    # Create the VM
    New-VM -Name $Name -MemoryStartupBytes $memoryInBytes -Generation 2 -SwitchName $SwitchName -Path "C:\VMs"

    # Add VHD
    Add-VMHardDiskDrive -VMName $Name -ControllerType SCSI -Path $VHDPath

    Write-Host "VM $Name created successfully with memory set to $MemoryStartupBytes."
}

# Function to load JSON and create VMs
function CreateVMsFromJSON {
    param (
        [Parameter(Mandatory=$true)]
        [string]$jsonPath,
        [Parameter(Mandatory=$true)]
        [string]$WimPath,
        [Parameter(Mandatory=$true)]
        [string]$Index
    )

    $jsonData = Get-Content -Path $jsonPath | ConvertFrom-Json

    foreach ($vm in $jsonData.VMs) {
        # Generate VHDX if it doesn't exist
        if (-not (Test-Path -Path $vm.VHDPath)) {
            New-SyspreppedVHDX -WimPath $WimPath -VHDXPath $vm.VHDPath -Size "60GB" -Index $Index
        }
        New-VMShell -Name $vm.Name -MemoryStartupBytes $vm.Memory -VHDPath $vm.VHDPath -SwitchName $vm.SwitchName
    }
}

# Example usage, change the paths to match your setup
$jsonFilePath = "C:\Scripts\vms.json"
$wimFilePath = "C:\install.wim"
$imageIndex = "1" # Index of the image to apply from the WIM file

CreateVMsFromJSON -jsonPath $jsonFilePath -WimPath $wimFilePath -Index $imageIndex
