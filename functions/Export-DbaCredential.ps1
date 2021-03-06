function Export-DbaCredential {
    <#
    .SYNOPSIS
        Exports credentials INCLUDING PASSWORDS, unless specified otherwise, to sql file.

    .DESCRIPTION
        Exports credentials INCLUDING PASSWORDS, unless specified otherwise, to sql file.

        Requires remote Windows access if exporting the password.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Credential
        Login to the target OS using alternative credentials. Accepts credential objects (Get-Credential)

    .PARAMETER Path
        The path to the exported sql file.

    .PARAMETER Identity
        The credentials to export. If unspecified, all credentials will be exported.

    .PARAMETER InputObject
        Allow credentials to be piped in from Get-DbaCredential

    .PARAMETER ExcludePassword
        Exports the SQL credential without any sensitive information.

    .PARAMETER Append
        Append to Path

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Credential
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        PS C:\> Export-DbaCredential -SqlInstance sql2017 -Path C:\temp\cred.sql

        Exports credentials, including passwords, from sql2017 to the file C:\temp\cred.sql

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [string[]]$Identity,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [switch]$ExcludePassword,
        [switch]$Append,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Credential[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $serverArray = @()
        $credentialArray = @{}
        $credentialCollection = New-Object System.Collections.ArrayList
    }
    process {
        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a Credential or specify a SqlInstance"
            return
        }

        if (Test-Bound -ParameterName SqlInstance) {
            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 9

                    $serverCreds = $server.Credentials
                    if (Test-Bound -ParameterName Identity) {
                        $serverCreds = $serverCreds | Where-Object Identity -in $Identity
                    }

                    $InputObject += $serverCreds
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
            }
        }

        foreach ($input in $InputObject) {
            $server = $input.Parent
            $instance = $server.Name

            if ($serverArray -notcontains $instance) {
                try {
                    if ($ExcludePassword) {
                        $serverCreds = $server.Credentials
                        $creds = New-Object System.Collections.ArrayList

                        foreach ($cred in $server.Credentials) {
                            $credObject = [PSCustomObject]@{
                                Name     = '[' + $cred.name + ']'
                                Identity = $cred.Id.ToString()
                                Password = ''
                            }
                            $creds.Add($credObject) | Out-Null
                        }
                        $creds | Add-Member -MemberType NoteProperty -Name 'SqlInstance' -Value $instance
                        $creds | Add-Member -MemberType NoteProperty -Name 'ExcludePassword' -Value $ExcludePassword
                        $credentialCollection.Add($credObject) | Out-Null
                    } else {
                        if (!(Test-SqlSa -SqlInstance $server)) {
                            Stop-Function -Message "Not a sysadmin on $instance. Quitting." -Target $instance -Continue
                        }

                        Write-Message -Level Verbose -Message "Getting NetBios name for $instance."
                        $sourceNetBios = Resolve-NetBiosName $server

                        Write-Message -Level Verbose -Message "Checking if Remote Registry is enabled on $instance."
                        try {
                            Invoke-Command2 -Raw -Credential $Credential -ComputerName $sourceNetBios -ScriptBlock { Get-ItemProperty -Path "HKLM:\SOFTWARE\" } -ErrorAction Stop
                        } catch {
                            Stop-Function -Message "Can't connect to registry on $instance." -Target $sourceNetBios -ErrorRecord $_
                            return
                        }

                        $creds = Get-DecryptedObject -SqlInstance $server -Type Credential
                        Write-Message -Level Verbose -Message "Adding Members"
                        $creds | Add-Member -MemberType NoteProperty -Name 'SqlInstance' -Value $instance
                        $creds | Add-Member -MemberType NoteProperty -Name 'ExcludePassword' -Value $ExcludePassword
                        $credentialCollection.Add($creds) | Out-Null
                    }
                } catch {
                    Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                }

                $serverArray += $instance

                $key = $input.Parent.Name + '::[' + $input.Name + ']'
                $credentialArray.add( $key, $true )
            } else {
                $key = $input.Parent.Name + '::[' + $input.Name + ']'
                $credentialArray.add( $key, $true )
            }
            $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
            $path = Join-DbaPath -Path $Path -Child "$($server.name.replace('\', '$'))-$timenow-credential.sql"
        }
    }

    end {
        $sql = @()
        foreach ($cred in $credentialCollection) {
            Write-Message -Level Verbose -Message "Credentials in object = $($cred.Count)"
            if (-not (Test-Bound -ParameterName Path)) {
                $time = (Get-Date -Format yyyMMddHHmmss)
                $mydocs = [Environment]::GetFolderPath('MyDocuments')
                $serverName = $($cred[0].SqlInstance.replace('\', '$'))
                $path = Join-DbaPath -Path $mydocs "$serverName-$time-credential.sql"
            }

            foreach ($currentCred in $creds) {
                $key = $currentCred.SqlInstance + '::' + $currentCred.Name
                if ( $credentialArray.ContainsKey($key) ) {
                    $name = $currentCred.Name.Replace("'", "''")
                    $identity = $currentCred.Identity.Replace("'", "''")
                    if ($currentCred.ExcludePassword) {
                        $sql += "CREATE CREDENTIAL $name WITH IDENTITY = N'$identity', SECRET = N'<EnterStrongPasswordHere>'"
                    } else {
                        $password = $currentCred.Password.Replace("'", "''")
                        $sql += "CREATE CREDENTIAL $name WITH IDENTITY = N'$identity', SECRET = N'$password'"
                    }

                    Write-Message -Level Verbose -Message "Created Script for $name"
                }
            }

            try {
                if ($Append) {
                    Add-Content -Path $path -Value $sql
                } else {
                    Set-Content -Path $path -Value $sql
                }
            } catch {
                Stop-Function -Message "Can't write to $path" -ErrorRecord $_ -Continue
            }

            Write-Message -Level Verbose -Message "Credentials exported to $path"
        }
    }

}