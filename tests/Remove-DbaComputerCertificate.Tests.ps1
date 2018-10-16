﻿$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 6
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Remove-DbaComputerCertificate).Parameters.Keys
        $knownParameters = 'ComputerName','Credential','Thumbprint','Store','Folder','EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Can remove a certificate" {
        BeforeAll {
            $null = Add-DbaComputerCertificate -Path $script:appveyorlabrepo\certificates\localhost.crt -Confirm:$false
            $thumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        }

        $results = Remove-DbaComputerCertificate -Thumbprint $thumbprint -Confirm:$false

        It "returns the store Name" {
            $results.Store -eq "LocalMachine" | Should Be $true
        }
        It "returns the folder Name" {
            $results.Folder -eq "My" | Should Be $true
        }

        It "reports the proper status of Removed" {
            $results.Status -eq "Removed" | Should Be $true
        }

        It "really removed it" {
            $results = Get-DbaComputerCertificate -Thumbprint $thumbprint
            $results | Should Be $null
        }
    }
}