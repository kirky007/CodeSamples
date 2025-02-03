[ScriptBlock]$Script = {

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Helper function to calculate gateway IP
    function Get-FirstAvailableSubnetIP {
        param (
            [string]$ip,
            [int]$cidr
        )
        # Parse the IP address and convert to byte array
        $ipBytes = [System.Net.IPAddress]::Parse($ip).GetAddressBytes()
        # Calculate the subnet mask in byte array format
        $maskBytes = [System.Net.IPAddress]::new([System.BitConverter]::GetBytes([System.Net.IPAddress]::HostToNetworkOrder(-bnot ([Math]::Pow(2, 32 - $cidr) - 1)))).GetAddressBytes()
        # Perform bitwise AND to get the network address
        $networkBytes = [byte[]]::new(4)
        for ($i = 0; $i -lt 4; $i++) {
            $networkBytes[$i] = $ipBytes[$i] -band $maskBytes[$i]
        }
        # Increment the last octet to get the first available IP address
        $networkBytes[3] += 1
        # Convert back to IP address and return as string
        [System.Net.IPAddress]::new($networkBytes).ToString()
    }

    # Validate DNS IPs
    function Validate-DNSIPs {
        param (
            [string]$dnsIPs
        )
        $ipPattern = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
        $ips = $dnsIPs -split ","
        foreach ($ip in $ips) {
            if (-not ($ip -match $ipPattern)) {
                return $false
            }
        }
        return $true
    }

    # Define the form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Deployed ICT Server Configuration Form"
    $form.Size = New-Object System.Drawing.Size(500,410)
    $form.StartPosition = "CenterScreen"

    # Set regex patterns for IP address and CIDR
    $ipPattern = "^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"
    $cidrPattern = "^(3[0-2]|[1-2]?[0-9]|[0-9])$"

    # Input box for form description
    $formNameLabel = New-Object System.Windows.Forms.Label
    $formNameLabel.Location = New-Object System.Drawing.Point(10,10)
    $formNameLabel.Size = New-Object System.Drawing.Size(410,40)
    $formNameLabel.Text = "Complete the form below to configure server settings for deployment.  Ensure all fields are filled in correctly and click the Submit button to proceed with the build.`nThe Create VMs option is only available for Hyper-V server builds."  

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
    $computerNameTextBox.Add_TextChanged({
        if ($computerNameTextBox.Text.Length -ne 14) {
            $computerNameTextBox.BackColor = "Red"
        } else {
            $computerNameTextBox.BackColor = "White"
            if ($computerNameTextBox.Text -match ".*(hx|hc).*") {
                $createVMSCheckbox.Enabled = $true
            } else {
                $createVMSCheckbox.Enabled = $false
            }
        }
    })

    # Input box for IP Address
    $ipAddressLabel = New-Object System.Windows.Forms.Label
    $ipAddressLabel.Location = New-Object System.Drawing.Point(10,130)
    $ipAddressLabel.Size = New-Object System.Drawing.Size(100,20)
    $ipAddressLabel.Text = "IP Address:"

    $ipAddressTextBox = New-Object System.Windows.Forms.TextBox
    $ipAddressTextBox.Location = New-Object System.Drawing.Point(110,130)
    $ipAddressTextBox.Size = New-Object System.Drawing.Size(110,20)
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
    $cidrLabel.Location = New-Object System.Drawing.Point(10,150)
    $cidrLabel.Size = New-Object System.Drawing.Size(100,20)
    $cidrLabel.Text = "Subnet CIDR:"

    $cidrTextBox = New-Object System.Windows.Forms.TextBox
    $cidrTextBox.Location = New-Object System.Drawing.Point(110,150)
    $cidrTextBox.Size = New-Object System.Drawing.Size(110,20)
    $cidrTextBox.Add_TextChanged({
        if ($cidrTextBox.Text -match $cidrPattern -and $ipAddressTextBox.Text -match $ipPattern) {
            $cidrTextBox.BackColor = "White"
            $gatewayTextBox.Text = Get-FirstAvailableSubnetIP -ip $ipAddressTextBox.Text -cidr $cidrTextBox.Text
        } elseif ($cidrTextBox.Text -match $cidrPattern) {
            $cidrTextBox.BackColor = "White"
        } else {
            $cidrTextBox.BackColor = "Red"
            $gatewayTextBox.Text = ""
        }
    })

    # Input box for Gateway IP (read-only)
    $gatewayLabel = New-Object System.Windows.Forms.Label
    $gatewayLabel.Location = New-Object System.Drawing.Point(10,170)
    $gatewayLabel.Size = New-Object System.Drawing.Size(100,20)
    $gatewayLabel.Text = "Gateway IP:"

    $gatewayTextBox = New-Object System.Windows.Forms.TextBox
    $gatewayTextBox.Location = New-Object System.Drawing.Point(110,170)
    $gatewayTextBox.Size = New-Object System.Drawing.Size(110,20)
    $gatewayTextBox.ReadOnly = $true

    # Input box for DNS IPs
    $dnsLabel = New-Object System.Windows.Forms.Label
    $dnsLabel.Location = New-Object System.Drawing.Point(10,190)
    $dnsLabel.Size = New-Object System.Drawing.Size(100,20)
    $dnsLabel.Text = "DNS IPs:"

    $dnsTextBox = New-Object System.Windows.Forms.TextBox
    $dnsTextBox.Location = New-Object System.Drawing.Point(110,190)
    $dnsTextBox.Size = New-Object System.Drawing.Size(200,20)
    $dnsTextBox.Add_TextChanged({
        if (Validate-DNSIPs -dnsIPs $dnsTextBox.Text) {
            $dnsTextBox.BackColor = "White"
        } else {
            $dnsTextBox.BackColor = "Red"
        }
    })

    # Checkbox for VM creation
    $createVMSCheckbox = New-Object System.Windows.Forms.CheckBox
    $createVMSCheckbox.Location = New-Object System.Drawing.Point(10,220)
    $createVMSCheckbox.Size = New-Object System.Drawing.Size(150,20)
    $createVMSCheckbox.Text = "Create VMs"
    $createVMSCheckbox.Enabled = $false

    # Button to capture values
    $submitButton = New-Object System.Windows.Forms.Button
    $submitButton.Location = New-Object System.Drawing.Point(10,270)
    $submitButton.Size = New-Object System.Drawing.Size(75,23)
    $submitButton.Text = "Submit"
    $submitButton.Add_Click({
        # Check no invalid inputs
        if ($computerNameTextBox.BackColor -eq "Red" -or $ipAddressTextBox.BackColor -eq "Red" -or $cidrTextBox.BackColor -eq "Red" -or $dnsTextBox.BackColor -eq "Red") {
            [System.Windows.Forms.MessageBox]::Show("Please correct the invalid inputs", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        } elseif (($computerNameTextBox.Text -eq $null -or $ipAddressTextBox.Text -eq $null -or $cidrTextBox.Text -eq $null -or $dnsTextBox.Text -eq $null) -or ($computerNameTextBox.Text -eq "" -or $ipAddressTextBox.Text -eq "" -or $cidrTextBox.Text -eq "" -or $dnsTextBox.Text -eq "")) {
            [System.Windows.Forms.MessageBox]::Show("Please fill in all the fields", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }
        else {
            $formValues = [PSCustomObject]@{
                BuildOSVer = if ($server2022RadioButton.Checked) { "Server 2022" } else { "Server 2025" }
                ComputerName = $computerNameTextBox.Text
                IPAddress = $ipAddressTextBox.Text
                CIDR = $cidrTextBox.Text
                GatewayIP = $gatewayTextBox.Text
                DNSIPs = $dnsTextBox.Text
                CreateVMs = $createVMSCheckbox.Checked
            }
            $formValues | ConvertTo-Json | Set-Content -Path .\vars.json

            [System.Windows.Forms.MessageBox]::Show("Values submitted successfully", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    

    })

    # Add controls to form
    $form.Controls.Add($formNameLabel)
    $form.Controls.Add($server2022RadioButton)
    $form.Controls.Add($server2025RadioButton)
    $form.Controls.Add($computerNameLabel)
    $form.Controls.Add($computerNameTextBox)
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

    # Show the form
    $form.ShowDialog()
}

$CaptureVars = powershell.exe -Wait -NoProfile -ExecutionPolicy Bypass -Command $Script
