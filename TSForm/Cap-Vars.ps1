#########################################
# Server Prestart script
# Requires four inputs: Environment, Server Name, and IP address/CIDR eg 10.84.64.161/24, and whether to prestage VM shells
# NOTE: Don't use double quotes ("") inside of (), as the nested scriptblock/spawned powershell process strips them - use single quotes only ('')
#########################################

# Scriptblock has 12k character limit, so using Standard Input piped to powershell to circumvent this limit - block is prefaced with @' and ends with '@ then piped to powershell.  
# the powershell.exe -command parameter with "-" accepts this piped standard input.
#@'
    # Hide progress bar
    $TSProgressUI = New-Object -COMObject Microsoft.SMS.TSProgressUI
    $TSProgressUI.CloseProgressDialog()
    # Register TSEnvironment to capture script outputs into TS vars
    $TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
    $logPath = $TSEnv.Value('_SMSTSLogPath')
    $logFile = "$logpath\SOE_CaptureStartupVars.log"
    
    #Vars for Witness card handling (on XR4000 chassis)
    $Model = (Get-WmiObject -class Win32_ComputerSystem).Model
    $TSMedia = $TSEnv.value('_SMSTSMediaType')      # FullMedia = USB/CD boot source

    # SupportedEnvironments poplated from 2nd step in build TS "Set Task Sequence Base Variables"
    $SupportedEnvironments = $TSEnv.Value('SupportedEnvironments')
    #$SupportedEnvironments = "JDEC,JDEP,JDEP,DDNU,DIEP,DIES,FIEP,FIES"

    "Capture Startup Variables script starting, loading Windows.Forms" | Out-File $logFile
    "Computer model: $Model" | Out-File $logFile -Append

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Helper function to calculate gateway IP
    function Get-FirstAvailableSubnetIP {
        param (
            [string]$ip,
            [int]$cidr
        )
            Try {
                $ErrorActionPreference = 'Stop'
                # Parse the IP address and convert to byte array
                $ipBytes = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
                # Calculate the subnet mask in byte array format
                $maskBytes = [System.Net.IPAddress]::new([System.BitConverter]::GetBytes([System.Net.IPAddress]::HostToNetworkOrder(-bnot ([Math]::Pow(2, 32 - $cidr) - 1)))).GetAddressBytes()
                # Perform bitwise AND to get the network address
                $networkBytes = [byte[]]::new(4)
                for ($i = 0; $i -lt 4; $i++) { $networkBytes[$i] = $ipBytes[$i] -band $maskBytes[$i] }
                # Increment the last octet to get the first available IP address
                $networkBytes[3] += 1
                # Convert back to IP address and return as string
                [System.Net.IPAddress]::new($networkBytes).ToString()
            } Catch {
                Return 'Error - check CIDR/IP'
            }
        }

    # Validate DNS IPs
    function Validate-DNSIPs {
        param (
            [string]$dnsIPs
        )
        $ipPattern = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
        $ips = $dnsIPs -split ","
        foreach ($ip in $ips) {
            if (-not ($ip -match $ipPattern)) { return $false }
        }
        return $true
    }

    # Define the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Deployed ICT Server Configuration Form"
    $form.Size = New-Object System.Drawing.Size(550,520)
    $form.StartPosition = "CenterScreen"
    # Set regex patterns for IP address and CIDR
    $ipPattern = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
    $cidrPattern = "^(3[0-2]|[1-2]?[0-9]|[0-9])$"

    # Input box for form description
    $formNameLabel = New-Object System.Windows.Forms.Label
    $formNameLabel.Location = New-Object System.Drawing.Point(10,10)
    $formNameLabel.Size = New-Object System.Drawing.Size(410,40)
    $formNameLabel.Text = "Ensure all fields are filled in correctly and click the Submit button to proceed with the build."  
    
    # Input box for info (model/cec/domain) tag at bottom of form
    $formInfoLabel = New-Object System.Windows.Forms.Label
    $formInfoLabel.Location = New-Object System.Drawing.Point(10,380)
    $formInfoLabel.Size = New-Object System.Drawing.Size(490,40)
    $formInfoLabel.Text = "`nModel: $Model"

    # Radio buttons for server version selection
    $server2022RadioButton = New-Object System.Windows.Forms.RadioButton
    $server2022RadioButton.Location = New-Object System.Drawing.Point(10,60)
    $server2022RadioButton.Size = New-Object System.Drawing.Size(100,20)
    $server2022RadioButton.Text = "Server 2022"
    $server2025RadioButton = New-Object System.Windows.Forms.RadioButton
    $server2025RadioButton.Location = New-Object System.Drawing.Point(10,80)
    $server2025RadioButton.Size = New-Object System.Drawing.Size(100,20)
    $server2025RadioButton.Text = "Server 2025"
    $server2025RadioButton.Checked = $true

    # Input box for computer name
    $computerNameLabel = New-Object System.Windows.Forms.Label
    $computerNameLabel.Location = New-Object System.Drawing.Point(10,110)
    $computerNameLabel.Size = New-Object System.Drawing.Size(100,20)
    $computerNameLabel.Text = "Server Name:"
    $computerNameTextBox = New-Object System.Windows.Forms.TextBox
    $computerNameTextBox.Location = New-Object System.Drawing.Point(110,110)
    $computerNameTextBox.Size = New-Object System.Drawing.Size(110,20)
    $computerNameTextBox.BackColor = "Red"
    $computerNameTextBox.Add_TextChanged({
        if ($computerNameTextBox.Text -ne $null -and $computerNameTextBox.Text -ne "") {      # get current selection start/length for restoration later (prevents cursor jumping around in textbox)
            $start = $computerNameTextBox.SelectionStart
            $length = $computerNameTextBox.SelectionLength    
        }
        if ($computerNameTextBox.Text.Length -ne 14) {               # needs to be 14 characters in length
            $computerNameTextBox.BackColor = "Red"
            $formInfoLabel.Text = "`nModel: $Model"
        } else {
            $computerNameTextBox.BackColor = "White"
            $computerNameTextBox.Text = $computerNameTextBox.Text.ToUpper()
            $computerNameTextBox.SelectionStart = $start
            $computerNameTextBox.SelectionLength = $length
            $global:CEC = $computerNameTextBox.Text.Substring(4,3).ToUpper()
            #If ($Model -eq 'PowerEdge XR4510c' -and $TSMedia -eq 'FullMedia' ) {
            if ($Model -eq 'Virtual Machine' ) {
                # Determine Witness computer name based off XR4510c cluster node, 010x = 0001, 020x = 0002, etc
                 $WITcomputerNameTextBox.Text = $computerNameTextBox.Text.SubString(0,4) + $global:CEC + 'HW' + $computerNameTextBox.Text.SubString(9,1) + '000' + $computerNameTextBox.Text.SubString(11,1)
             }
            if ($DomainTextBox.BackColor -eq "White") {
                $formInfoLabel.Text = "CEC: $global:CEC, Netbios Domain: $global:NetbiosDomain, FQDN: $global:FQDN `nModel: $Model"
            }
            if ($computerNameTextBox.Text -match ".*(hx|hc).*") { 
                $createVMSCheckbox.Enabled = $true 
            } else { 
                $createVMSCheckbox.Enabled = $false 
            }
        }
    })

    # Input box for Netbios Domain
    $DomainLabel = New-Object System.Windows.Forms.Label
    $DomainLabel.Location = New-Object System.Drawing.Point(10,130)
    $DomainLabel.Size = New-Object System.Drawing.Size(100,20)
    $DomainLabel.Text = "NetBios Domain:"
    $DomainTextBox = New-Object System.Windows.Forms.TextBox
    $DomainTextBox.Location = New-Object System.Drawing.Point(110,130)
    $DomainTextBox.Size = New-Object System.Drawing.Size(110,20)
    $DomainTextBox.BackColor = "Red"
    $DomainTextBox.Add_TextChanged({
        if ($DomainTextBox.Text -ne $null -and $DomainTextBox.Text -ne "") {              # get current selection start/length for restoration later (prevents cursor jumping around in textbox)
            $start = $DomainTextBox.SelectionStart
            $length = $DomainTextBox.SelectionLength    
        }
        if ($DomainTextBox.Text.Length -lt 3 -or $DomainTextBox.Text.Length -gt 4) {      # needs to be 3 or 4 characters in length
            $DomainTextBox.BackColor = "Red"
            $formInfoLabel.Text = "`nModel: $Model"
        } else {
            $DomainTextBox.BackColor = "White"
            $DomainTextBox.Text = $DomainTextBox.Text.ToUpper()
            $DomainTextBox.SelectionStart = $start
            $DomainTextBox.SelectionLength = $length
            $global:NetBiosDomain = $DomainTextBox.Text
            If ($SupportedEnvironments -match $NetBiosDomain) {
                $global:FQDN = "$NetBiosDomain.MIL.AU"
            } else {
                $global:FQDN = "$NetBiosDomain.$($computerNameTextBox.Text.Substring(0,4)).MIL.AU"
            }
            if ($computerNameTextBox.BackColor -eq "White") {
                $formInfoLabel.Text = "CEC: $global:CEC, Netbios Domain: $global:NetbiosDomain, FQDN: $global:FQDN `nModel: $Model"
            }
        }
    })

    # Input box for IP Address
    $ipAddressLabel = New-Object System.Windows.Forms.Label
    $ipAddressLabel.Location = New-Object System.Drawing.Point(10,150)
    $ipAddressLabel.Size = New-Object System.Drawing.Size(100,20)
    $ipAddressLabel.Text = "IP Address:"
    $ipAddressTextBox = New-Object System.Windows.Forms.TextBox
    $ipAddressTextBox.Location = New-Object System.Drawing.Point(110,150)
    $ipAddressTextBox.Size = New-Object System.Drawing.Size(110,20)
    $ipAddressTextBox.BackColor = "Red"
    $ipAddressTextBox.Add_TextChanged({
        if ($ipAddressTextBox.Text -match $ipPattern -and $cidrTextBox.Text -match $cidrPattern) {
            $ipAddressTextBox.BackColor = "White"
            $gatewayTextBox.Text = Get-FirstAvailableSubnetIP -ip $ipAddressTextBox.Text -cidr $cidrTextBox.Text
        } elseif ($ipAddressTextBox.Text -match $ipPattern) { 
            $ipAddressTextBox.BackColor = "White"
        } else {
            $ipAddressTextBox.BackColor = "Red"
            $gatewayTextBox.Text = ""
        }
    })

    # Input box for Subnet CIDR
    $cidrLabel = New-Object System.Windows.Forms.Label
    $cidrLabel.Location = New-Object System.Drawing.Point(10,170)
    $cidrLabel.Size = New-Object System.Drawing.Size(100,20)
    $cidrLabel.Text = "Subnet CIDR:"
    $cidrTextBox = New-Object System.Windows.Forms.TextBox
    $cidrTextBox.Location = New-Object System.Drawing.Point(110,170)
    $cidrTextBox.Size = New-Object System.Drawing.Size(25,20)
    $cidrTextBox.BackColor = "Red"
    $cidrTextBox.Add_TextChanged({
        if ($cidrTextBox.Text -match $cidrPattern -and $ipAddressTextBox.Text -match $ipPattern) {
            $cidrTextBox.BackColor = "White"
            $gatewayTextBox.Text = Get-FirstAvailableSubnetIP -ip $ipAddressTextBox.Text -cidr $cidrTextBox.Text
            If ($gatewayTextBox.Text -like "Error*") { 
                $gatewayTextBox.BackColor = "Red" 
            } else { 
                $gatewayTextBox.BackColor = ""
            }
        } elseif ($cidrTextBox.Text -match $cidrPattern) { 
                $cidrTextBox.BackColor = "White"
        } else {
                $cidrTextBox.BackColor = "Red"
                $gatewayTextBox.Text = ""
        }
    })

    # Input box for Gateway IP (read-only)
    $gatewayLabel = New-Object System.Windows.Forms.Label
    $gatewayLabel.Location = New-Object System.Drawing.Point(10,190)
    $gatewayLabel.Size = New-Object System.Drawing.Size(100,20)
    $gatewayLabel.Text = "Gateway IP:"
    $gatewayTextBox = New-Object System.Windows.Forms.TextBox
    $gatewayTextBox.Location = New-Object System.Drawing.Point(110,190)
    $gatewayTextBox.Size = New-Object System.Drawing.Size(110,20)
    $gatewayTextBox.ReadOnly = $true

    # Input box for DNS IPs
    $dnsLabel = New-Object System.Windows.Forms.Label
    $dnsLabel.Location = New-Object System.Drawing.Point(10,210)
    $dnsLabel.Size = New-Object System.Drawing.Size(100,20)
    $dnsLabel.Text = "DNS IPs:"
    $dnsTextBox = New-Object System.Windows.Forms.TextBox
    $dnsTextBox.Location = New-Object System.Drawing.Point(110,210)
    $dnsTextBox.Size = New-Object System.Drawing.Size(200,20)
    $dnsTextBox.BackColor = "Red" 
    $dnsTextBox.Add_TextChanged({
        if (Validate-DNSIPs -dnsIPs $dnsTextBox.Text) { 
            $dnsTextBox.BackColor = "White" 
        } else { 
            $dnsTextBox.BackColor = "Red" 
        }
    })

    # Checkbox for VM creation
    $createVMSCheckbox = New-Object System.Windows.Forms.CheckBox
    $createVMSCheckbox.Location = New-Object System.Drawing.Point(10,230)
    $createVMSCheckbox.Size = New-Object System.Drawing.Size(150,20)
    $createVMSCheckbox.Text = "Create VMs"
    $createVMSCheckbox.Enabled = $false

    ###################################
    #   Witness card form handling    #
    ###################################

    # Input box for Witness computer name
    $WITcomputerNameLabel = New-Object System.Windows.Forms.Label
    $WITcomputerNameLabel.Location = New-Object System.Drawing.Point(10,270)
    $WITcomputerNameLabel.Size = New-Object System.Drawing.Size(330,20)
    $WITcomputerNameLabel.Text = "XR4510c server detected, Witness sled configuration: `nWitness Server Name:"
    $WITcomputerNameTextBox = New-Object System.Windows.Forms.TextBox
    $WITcomputerNameTextBox.Location = New-Object System.Drawing.Point(150,290)
    $WITcomputerNameTextBox.Size = New-Object System.Drawing.Size(110,20)
    $WITcomputerNameTextBox.ReadOnly = $true

    # Input box for Witness IP Address
    $WITipAddressLabel = New-Object System.Windows.Forms.Label
    $WITipAddressLabel.Location = New-Object System.Drawing.Point(10,310)
    $WITipAddressLabel.Size = New-Object System.Drawing.Size(130,20)
    $WITipAddressLabel.Text = "Witness IP Address:"
    $WITipAddressTextBox = New-Object System.Windows.Forms.TextBox
    $WITipAddressTextBox.Location = New-Object System.Drawing.Point(150,310)
    $WITipAddressTextBox.Size = New-Object System.Drawing.Size(110,20)
    $WITipAddressTextBox.BackColor = "Red"
    $WITipAddressTextBox.Add_TextChanged({
        if ($WITipAddressTextBox.Text -match $ipPattern -and $WITcidrTextBox.Text -match $cidrPattern) {
            $WITipAddressTextBox.BackColor = "White"
            $WITgatewayTextBox.Text = Get-FirstAvailableSubnetIP -ip $WITipAddressTextBox.Text -cidr $WITcidrTextBox.Text
        } elseif ($WITipAddressTextBox.Text -match $ipPattern) { 
            $WITipAddressTextBox.BackColor = "White"
        } else {
            $WITipAddressTextBox.BackColor = "Red"
            $WITgatewayTextBox.Text = ""
        }
    })

    # Input box for Witness Subnet CIDR
    $WITcidrLabel = New-Object System.Windows.Forms.Label
    $WITcidrLabel.Location = New-Object System.Drawing.Point(10,330)
    $WITcidrLabel.Size = New-Object System.Drawing.Size(130,20)
    $WITcidrLabel.Text = "Witness Subnet CIDR:"
    $WITcidrTextBox = New-Object System.Windows.Forms.TextBox
    $WITcidrTextBox.Location = New-Object System.Drawing.Point(150,330)
    $WITcidrTextBox.Size = New-Object System.Drawing.Size(25,20)
    $WITcidrTextBox.BackColor = "Red"
    $WITcidrTextBox.Add_TextChanged({
        if ($WITcidrTextBox.Text -match $cidrPattern -and $WITipAddressTextBox.Text -match $ipPattern) {
            $WITcidrTextBox.BackColor = "White"
            $WITgatewayTextBox.Text = Get-FirstAvailableSubnetIP -ip $WITipAddressTextBox.Text -cidr $WITcidrTextBox.Text
            If ($WITgatewayTextBox.Text -like "Error*") { 
                $WITgatewayTextBox.BackColor = "Red"
            } else { 
                $WITgatewayTextBox.BackColor = ""
            }
        } elseif ($WITcidrTextBox.Text -match $cidrPattern) { 
                $WITcidrTextBox.BackColor = "White"
        } else {
                $WITcidrTextBox.BackColor = "Red"
                $WITgatewayTextBox.Text = ""
        }
    })
    
    # Input box for Gateway IP (read-only)
    $WITgatewayLabel = New-Object System.Windows.Forms.Label
    $WITgatewayLabel.Location = New-Object System.Drawing.Point(10,350)
    $WITgatewayLabel.Size = New-Object System.Drawing.Size(130,20)
    $WITgatewayLabel.Text = "Witness Gateway IP:"
    $WITgatewayTextBox = New-Object System.Windows.Forms.TextBox
    $WITgatewayTextBox.Location = New-Object System.Drawing.Point(150,350)
    $WITgatewayTextBox.Size = New-Object System.Drawing.Size(110,20)
    $WITgatewayTextBox.ReadOnly = $true

    ###################################
    #   Submit form validation        #
    ###################################

    # Button to Submit form
    $submitButton = New-Object System.Windows.Forms.Button
    $submitButton.Location = New-Object System.Drawing.Point(300,370)
    $submitButton.Size = New-Object System.Drawing.Size(75,25)
    $submitButton.Text = "Submit"
    $submitButton.Add_Click({
        # Check no invalid inputs
        if ($computerNameTextBox.BackColor -eq "Red" -or $ipAddressTextBox.BackColor -eq "Red" -or $cidrTextBox.BackColor -eq "Red" -or $dnsTextBox.BackColor -eq "Red" -or $gatewayTextBox.BackColor -eq "Red") {
            [System.Windows.Forms.MessageBox]::Show("Please correct the invalid inputs", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        } elseif (($computerNameTextBox.Text -eq $null -or $ipAddressTextBox.Text -eq $null -or $cidrTextBox.Text -eq $null -or $dnsTextBox.Text -eq $null) -or ($computerNameTextBox.Text -eq "" -or $ipAddressTextBox.Text -eq "" -or $cidrTextBox.Text -eq "" -or $dnsTextBox.Text -eq "")) {
            [System.Windows.Forms.MessageBox]::Show("Please fill in all the fields", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        } else {
            $formValues = [PSCustomObject]@{
                BuildOSVer = if ($server2022RadioButton.Checked) { "Server 2022" } else { "Server 2025" }
                ComputerName = $computerNameTextBox.Text
                IPAddress = $ipAddressTextBox.Text
                CIDR = $cidrTextBox.Text
                GatewayIP = $gatewayTextBox.Text
                DNSIPs = $dnsTextBox.Text
                CreateVMs = $createVMSCheckbox.Checked
            }
            $formValues | ConvertTo-Json | Set-Content -Path $logPath\SOE_CaptureStartupVars.json -Force
            $global:formSuccess = $true
            $form.Close()
        }
    })

    # Add controls to form
    $form.Controls.Add($formNameLabel)
    $form.Controls.Add($formInfoLabel)
    $form.Controls.Add($server2022RadioButton)
    $form.Controls.Add($server2025RadioButton)
    $form.Controls.Add($computerNameLabel)
    $form.Controls.Add($computerNameTextBox)
    $form.Controls.Add($DomainLabel)
    $form.Controls.Add($DomainTextBox)
    $form.Controls.Add($ipAddressLabel)
    $form.Controls.Add($ipAddressTextBox)
    $form.Controls.Add($cidrLabel)
    $form.Controls.Add($cidrTextBox)
    $form.Controls.Add($gatewayLabel)
    $form.Controls.Add($gatewayTextBox)
    $form.Controls.Add($dnsLabel)
    $form.Controls.Add($dnsTextBox)
    $form.Controls.Add($createVMSCheckbox)
    $form.Controls.Add($submitButton)
    #If ($Model -eq 'PowerEdge XR4510c' -and $TSMedia -eq 'FullMedia' ) {
    If ($Model -eq 'Virtual Machine' ) {
        $form.Controls.Add($WITcomputerNameLabel)
        $form.Controls.Add($WITcomputerNameTextBox)
        $form.Controls.Add($WITipAddressLabel)
        $form.Controls.Add($WITipAddressTextBox)
        $form.Controls.Add($WITcidrLabel)
        $form.Controls.Add($WITcidrTextBox)
        $form.Controls.Add($WITgatewayLabel)
        $form.Controls.Add($WITgatewayTextBox)
    }
    # Show the form
    $form.ShowDialog()

    if ($global:formSuccess) {
        "Capture Startup Variables script completed succesfully, refer to CaptureStartupVars.json for vars captured via the form." | Out-File $logFile -Append
        exit 0
    } else { 
        "Capture Startup Variables script failed/cancelled, aborting build!" | Out-File $logFile -Append
        exit 1
    }

#'@ | powershell -noprofile -Command -

#$CaptureVars = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $Script

If ($lastexitcode -eq 0) {
    # All good, continue build
    Exit 0
} else {
    # Fail build
    Exit 1
}

 # If building a PowerEdge XR4510c HyperV node, we need to capture the CECC environment for the XR4000W unattended witness builds (stored on the build USB under .\Witness)
    # There is one witness sled (witness model = XR4000W) per Dell chassis
    $Model = (Get-WmiObject -class Win32_ComputerSystem).Model
    $TSMedia = $TSEnv.value('_SMSTSMediaType')      # FullMedia = USB/CD boot source
    If ($Model -eq 'PowerEdge XR4510c' -and $TSMedia -eq 'FullMedia' ) {
        # Ensure we get the correct drive letter for the writable build USB boot volume
        $USBDriveLetter = (Get-Volume | Where {$_.FileSystem -eq 'FAT32' -and $_.DriveType -eq 'Removable'}).DriveLetter + ':'   
        If ($USBDriveLetter) {
            New-Item -Type Directory -Path "$USBDriveLetter\Witness" -Force -ErrorAction SilentlyContinue | Out-Null
            Switch ($CompName.SubString(10,4)) {  # grab numeric section of computer name to determine the cluster / chassis to base witness name from
                "0101"   { $WitNumber = "0001" }
                "0201"   { $WitNumber = "0002" }
                "0301"   { $WitNumber = "0003" }
                "0401"   { $WitNumber = "0004" }
                default { $WitNumber = "0001" }
            }

            [String]$WitCompName = $CompName.SubString(0,4) + $CEC + 'WIT' + $WitNumber
            # Display XR4000w witness unattended configuration settings for validation
            Write-Host "`n`n"
            Write-Host 'Dell PowerEdge XR4000 system detected, chassis contains a Witness sled.'
            Write-Host -ForegroundColor Yellow "Witness sled pre-populated configuration settings:"  
            Write-Host -ForegroundColor Green "`t Server OS `t`t : Windows Server $BuildOSVer"
            Write-Host -ForegroundColor Green "`t Server Name `t`t : $WitCompName"
            Write-Host -ForegroundColor Green "`t AD Site/CEC `t`t : $CEC"
            Write-Host -ForegroundColor Green "`t Gateway IP `t`t : $GWIP"
            Write-Host -ForegroundColor Green "`t NetBios Domain Name `t : $NetBiosDomain"
            Write-Host -ForegroundColor Green "`t Domain FQDN `t`t : $DomainFQDN"
            
            # Request Witness IP
            $IpValid = $false
            While (!($IPValid)) {
                $WitsubnetInfo = $null
                $WitIPCIDR = $(Write-Host -ForegroundColor Yellow 'Witness IP Address/CIDR: ' -NoNewLine; Read-Host)
                $WitIP = ($WitIPCIDR.Split('/'))[0]
                $WitCIDR = ($WitIPCIDR.Split('/'))[1]
                if ($WitCIDR -eq $null) {
                    Write-Host -ForegroundColor Red 'No CIDR, please add a valid CIDR, i.e /24'
                    $IPValid = $false 
                    Continue
                }
                $WitsubnetInfo = Get-IPv4Subnet -IPAddress $WitIP -PrefixLength $WitCIDR
                #Write-Host "[$subNetInfo]"
                if ($WitsubnetInfo -eq 'Error' -or $WitsubnetInfo -eq $null -or $WitsubnetInfo -eq '') { 
                    Write-Host -ForegroundColor Red 'Invalid IP address, try again with a valid IP'
                    $IPValid = $false
                } else {
                    Write-Host -Foregroundcolor Green 'IP Address/CIDR format validated'
                    $IPValid = $true
                }
            }
            Write-Host "`n`n"
            Write-Host 'A config file will be generated on the Build USB in the .\Witness folder for use with the unattended headless witness build.'
            Write-Host 'Please edit this file if any of these setting require modification (in particular the IP and Witness computer name when building multiple Witnesses within the same CEC.)'
            Write-Host -ForegroundColor Yellow "Witness sled pre=populated configuration settings:"  
            Write-Host -ForegroundColor Green "`t Server OS `t`t : Windows Server $BuildOSVer"
            Write-Host -ForegroundColor Green "`t Server Name `t`t : $WitCompName"
            Write-Host -ForegroundColor Green "`t IP Address `t`t : $WitIP"
            Write-Host -ForegroundColor Green "`t Gateway IP `t`t : $GWIP"
            Write-Host -ForegroundColor Green "`t AD Site/CEC `t`t : $CEC"
            Write-Host -ForegroundColor Green "`t CIDR `t`t`t : $WitCIDR"
            Write-Host -ForegroundColor Green "`t NetBios Domain Name `t : $NetBiosDomain"
            Write-Host -ForegroundColor Green "`t Domain FQDN `t`t : $DomainFQDN"
            Write-Host "`n"
           
            # Write Witness config file to build usb
            [String]"$BuildOSVer,$WitCompName,$WitIP,$GWIP,$CEC,$WitCIDR,$NetBiosDomain,$DomainFQDN" | Out-File -FilePath "$USBDriveLetter\Witness\Witness.cfg" -Force

            # Log witness vars
            "Witness detected and configured with: " | Out-File -FilePath $logpath\SOE_CaptureStartupVars.log -Append
             [String]"$BuildOSVer,$WitCompName,$WitIP,$GWIP,$CEC,$WitCIDR,$NetBiosDomain,$DomainFQDN" | Out-File -FilePath $logpath\SOE_CaptureStartupVars.log -Append

            # Pause (press enter to continue)
            Pause
        }
    }
