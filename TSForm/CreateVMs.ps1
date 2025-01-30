# Define function to create VM based on parameters
function New-HyperVVMFromJSON {
    param (
        [Parameter(Mandatory=$true)]
        [string]$JsonFilePath
    )

    # Import the JSON file
    $jsonData = Get-Content -Path $JsonFilePath | ConvertFrom-Json

    # Loop through each hardware platform
    foreach ($platform in $jsonData.PSObject.Properties) {
        $hardwarePlatform = $platform.Name

        # Loop through each site type within the hardware platform
        foreach ($siteType in $platform.Value.PSObject.Properties) {
            $site = $siteType.Name

            # Loop through each server role within the site type
            foreach ($serverRole in $siteType.Value) {
                $vmName = "$hardwarePlatform-$site-$($serverRole.Role)"
                $memory = $serverRole.Memory
                $vhdSize = $serverRole.VHDSize
                $vCPUs = $serverRole.VCPUs
                $switchName = $serverRole.SwitchName

                # Generate a unique path for each VM
                $vmPath = "C:\VMs\$vmName"
                $vhdPath = "$vmPath\$vmName.vhdx"

                # Ensure the VM path exists
                if (-not (Test-Path -Path $vmPath)) {
                    New-Item -ItemType Directory -Path $vmPath -Force | Out-Null
                }

                Write-Host "Creating VM: $vmName"
                
                # Create the VM
                New-VM -Name $vmName -MemoryStartupBytes $memory -Path $vmPath -Generation 2 -SwitchName $switchName
                
                # Add a new VHD to the VM
                New-VHD -Path $vhdPath -SizeBytes $vhdSize -Dynamic | Out-Null
                Add-VMHardDiskDrive -VMName $vmName -Path $vhdPath
                
                # Set number of vCPUs
                Set-VM -Name $vmName -ProcessorCount $vCPUs

                Write-Host "VM $vmName created successfully."
            }
        }
    }
}

# Example usage - replace with your actual JSON file path
New-HyperVVMFromJSON -JsonFilePath "C:\path\to\your\jsonfile.json"
