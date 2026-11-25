BeforeAll {
    Import-Module -Name (Join-Path $PSScriptRoot '../../../src/Bylaw.psd1') -Force
}

AfterAll {
    Remove-Module -Name Bylaw -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-BylawJson (ADR-0009)' {
    It 'writes <Case>' -ForEach @(
        @{ Case = 'null'; Value = $null; Expected = 'null' }
        @{ Case = 'true'; Value = $true; Expected = 'true' }
        @{ Case = 'false'; Value = $false; Expected = 'false' }
        @{ Case = 'an integer'; Value = 42; Expected = '42' }
        @{ Case = 'a negative long'; Value = [long] -9000000000; Expected = '-9000000000' }
        @{ Case = 'a double'; Value = 0.1; Expected = '0.1' }
        @{ Case = 'an integral double'; Value = 5.0; Expected = '5' }
        @{ Case = 'a decimal'; Value = [decimal] '2.25'; Expected = '2.25' }
        @{ Case = 'a string'; Value = 'Disabled'; Expected = '"Disabled"' }
        @{ Case = 'an ARM expression unescaped'; Value = "[parameters('effect')]"; Expected = '"[parameters(''effect'')]"' }
        @{ Case = 'a path with slashes unescaped'; Value = '0.0.0.0/0'; Expected = '"0.0.0.0/0"' }
        # Built from char codes: source files stay ASCII so they need no BOM (PSScriptAnalyzer).
        @{ Case = 'non-ASCII as UTF-8 text'; Value = ('Caf' + [char] 0xE9 + ' ' + [char] 0x2713); Expected = ('"Caf' + [char] 0xE9 + ' ' + [char] 0x2713 + '"') }
        @{ Case = 'escaped quotes and backslashes'; Value = 'a"b\c'; Expected = '"a\"b\\c"' }
        @{ Case = 'escaped control characters'; Value = "a`tb`nc`r" + [char] 1; Expected = '"a\tb\nc\r\u0001"' }
        @{ Case = 'an empty object'; Value = @{}; Expected = '{}' }
        @{ Case = 'an empty array'; Value = @(); Expected = '[]' }
    ) {
        InModuleScope Bylaw -Parameters @{ Value = $Value; Expected = $Expected } {
            param($Value, $Expected)
            ConvertTo-BylawJson -InputObject $Value | Should -BeExactly "$Expected`n"
        }
    }

    It 'indents nested objects and arrays by two spaces with LF only' {
        InModuleScope Bylaw {
            $value = [ordered]@{
                if   = [ordered]@{ field = 'kind'; in = @('StorageV2', 'BlockBlobStorage') }
                then = [ordered]@{ effect = "[parameters('effect')]" }
            }
            $expected = @(
                '{'
                '  "if": {'
                '    "field": "kind",'
                '    "in": ['
                '      "StorageV2",'
                '      "BlockBlobStorage"'
                '    ]'
                '  },'
                '  "then": {'
                '    "effect": "[parameters(''effect'')]"'
                '  }'
                '}'
                ''
            ) -join "`n"
            $json = ConvertTo-BylawJson -InputObject $value
            $json | Should -BeExactly $expected
            $json.Contains("`r") | Should -BeFalse
        }
    }

    It 'keeps ordered dictionaries in insertion order' {
        InModuleScope Bylaw {
            $json = ConvertTo-BylawJson -InputObject ([ordered]@{ z = 1; a = 2 })
            $json | Should -BeExactly "{`n  `"z`": 1,`n  `"a`": 2`n}`n"
        }
    }

    It 'sorts hashtable keys by ordinal comparison' {
        InModuleScope Bylaw {
            $table = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
            $table['b'] = 1
            $table['B'] = 2
            $table['a'] = 3
            $table['_x'] = 4
            $json = ConvertTo-BylawJson -InputObject $table
            $keys = [regex]::Matches($json, '"([^"]+)":') | ForEach-Object { $_.Groups[1].Value }
            $keys | Should -Be @('B', '_x', 'a', 'b')
        }
    }

    It 'keeps PSCustomObject property order' {
        InModuleScope Bylaw {
            ConvertTo-BylawJson -InputObject ([pscustomobject]@{ second = 2; first = 1 }) |
                Should -BeExactly "{`n  `"second`": 2,`n  `"first`": 1`n}`n"
        }
    }

    It 'keeps a single-element array as an array' {
        InModuleScope Bylaw {
            ConvertTo-BylawJson -InputObject ([ordered]@{ in = @('only') }) |
                Should -BeExactly "{`n  `"in`": [`n    `"only`"`n  ]`n}`n"
        }
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'NaN'; Value = [double]::NaN }
        @{ Case = 'infinity'; Value = [double]::PositiveInfinity }
        @{ Case = 'a DateTime'; Value = [datetime]::new(2026, 1, 1) }
        @{ Case = 'a non-string key'; Value = @{ 1 = 'a' } }
    ) {
        InModuleScope Bylaw -Parameters @{ Value = $Value } {
            param($Value)
            $thrown = $null
            try {
                $null = ConvertTo-BylawJson -InputObject $Value
            }
            catch {
                $thrown = $_
            }
            $thrown | Should -Not -BeNullOrEmpty
        }
    }

    It 'gives identical output for identical input' {
        InModuleScope Bylaw {
            $value = @{ b = @(1, 2, @{ y = 'x'; x = 'y' }); a = [ordered]@{ q = $true } }
            ConvertTo-BylawJson -InputObject $value | Should -BeExactly (ConvertTo-BylawJson -InputObject $value)
        }
    }
}

Describe 'Write-BylawJsonFile' {
    It 'writes UTF-8 without BOM, creating the folder' {
        InModuleScope Bylaw -Parameters @{ Path = (Join-Path $TestDrive 'nested/out.json') } {
            param($Path)
            $cafe = 'Caf' + [char] 0xE9
            Write-BylawJsonFile -Path $Path -InputObject ([ordered]@{ name = $cafe })
            $bytes = [System.IO.File]::ReadAllBytes($Path)
            $bytes[0] | Should -Be ([byte] [char] '{')
            [System.Text.Encoding]::UTF8.GetString($bytes) | Should -BeExactly ("{`n  `"name`": `"" + $cafe + "`"`n}`n")
        }
    }
}
