# Wiki pages for build/build.ps1 (ADR-0037): a page per exported command (PlatyPS), a page per
# keyword (from its comment-based help, read inside the module), and the sidebar. Diagnostics pages
# are added from the catalogue in docs/diagnostics. tests/Build/Docs.Tests.ps1 generates every page.

# The name of the file in the wiki repository that lists the pages the build generated last time,
# so it only ever replaces or removes its own pages.
$script:GeneratedPagesFile = '.bylaw-generated-pages'

# Where keywords are used that don't say so in a Test-BylawParent call: values, and the Modify
# operations that check their parent through a helper.
$script:KeywordUsageFallback = @{
    AddOrReplace     = 'Modify'
    Remove           = 'Modify'
    Param            = 'Anywhere in a Policy or Initiative, as a value'
    Arm              = 'Anywhere in a Policy or Initiative, as a value'
    ResourceGroupTag = 'Anywhere in a Policy, as a value or piped to Must; and in PolicyDefinition -Parameters'
    Current          = 'Count -Where, as a value'
}

function Get-KeywordUsage {
    # Keyword name -> where it can be used, from the -Allowed lists of Test-BylawParent calls with
    # a literal -Keyword, and the fallback table for the rest (unless -SourceOnly).
    param([Parameter(Mandatory)] [string] $SourceRoot, [switch] $SourceOnly)

    $usage = @{}
    foreach ($file in Get-ChildItem -Path $SourceRoot -Recurse -Filter '*.ps1' -File) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $null, [ref] $null)
        $calls = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Test-BylawParent' }, $true)
        foreach ($call in $calls) {
            $elements = $call.CommandElements
            $keyword = $null
            $allowed = @()
            for ($i = 1; $i -lt $elements.Count; $i++) {
                if ($elements[$i] -isnot [System.Management.Automation.Language.CommandParameterAst] -or $i + 1 -ge $elements.Count) {
                    continue
                }
                $value = $elements[$i + 1]
                switch ($elements[$i].ParameterName) {
                    'Keyword' {
                        if ($value -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                            $keyword = $value.Value
                        }
                    }
                    'Allowed' {
                        $allowed = @($value.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object Value)
                    }
                }
            }
            if ($keyword -and $allowed.Count -gt 0) {
                $usage[$keyword] = ($allowed | ForEach-Object { if ($_ -eq 'Where') { 'Count -Where' } else { $_ } }) -join ', '
            }
        }
    }
    if ($SourceOnly) {
        return $usage
    }
    foreach ($name in $script:KeywordUsageFallback.Keys) {
        if (-not $usage.ContainsKey($name)) {
            $usage[$name] = $script:KeywordUsageFallback[$name]
        }
    }
    $usage
}

function Get-HelpText {
    # The text of a help field, which Get-Help gives as an object, an array of them, or a string.
    param([AllowNull()] [object] $Value)

    if ($null -eq $Value) {
        return ''
    }
    $parts = foreach ($item in @($Value)) {
        if ($item -is [string]) {
            $item
        }
        elseif ($item.PSObject.Properties['Text']) {
            $item.Text
        }
        else {
            "$item"
        }
    }
    (($parts | Where-Object { $_ }) -join "`n`n").Trim()
}

function ConvertTo-KeywordPage {
    # A keyword's wiki page from its Get-Help object, laid out like PlatyPS's command pages.
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [object] $Help,
        [Parameter(Mandatory)] [string] $UsedIn
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# $Name")
    $lines.Add('')
    $lines.Add('## SYNOPSIS')
    $lines.Add((Get-HelpText $Help.Synopsis))
    $lines.Add('')
    $lines.Add('## SYNTAX')
    $lines.Add('')
    $lines.Add('```')
    $syntax = (($Help.syntax | Out-String -Width 200) -split "`r?`n" | Where-Object { $_.Trim() }) -join "`n"
    $lines.Add($syntax.Trim())
    $lines.Add('```')
    $lines.Add('')
    $description = if ($Help.PSObject.Properties['description']) { Get-HelpText $Help.description } else { '' }
    if ($description) {
        $lines.Add('## DESCRIPTION')
        $lines.Add($description)
        $lines.Add('')
    }
    $lines.Add('## USED IN')
    $lines.Add($UsedIn)
    $lines.Add('')
    $lines.Add('## EXAMPLES')
    $lines.Add('')
    $number = 0
    foreach ($example in @($Help.examples.example)) {
        $number++
        $lines.Add("### Example $number")
        $lines.Add('```powershell')
        $lines.Add(((Get-HelpText $example.code) -replace "`r", '').TrimEnd())
        $lines.Add('```')
        $remarks = Get-HelpText $example.remarks
        if ($remarks) {
            $lines.Add('')
            $lines.Add($remarks)
        }
        $lines.Add('')
    }
    $parameters = @(if ($Help.parameters -and $Help.parameters.PSObject.Properties['parameter']) { $Help.parameters.parameter })
    if ($parameters.Count -gt 0) {
        $lines.Add('## PARAMETERS')
        $lines.Add('')
        foreach ($parameter in $parameters) {
            $lines.Add("### -$($parameter.name)")
            $lines.Add((Get-HelpText $parameter.description))
            $lines.Add('')
            $lines.Add('```yaml')
            $lines.Add("Type: $($parameter.type.name)")
            $lines.Add("Required: $($parameter.required)")
            $lines.Add("Position: $($parameter.position)")
            $lines.Add("Accept pipeline input: $($parameter.pipelineInput)")
            $lines.Add('```')
            $lines.Add('')
        }
    }
    (($lines -join "`n").TrimEnd() + "`n")
}

function New-WikiPageSet {
    # Writes every generated page to OutputPath: commands, keywords and the sidebar. Returns the page
    # names written, without .md.
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $SourceRoot,
        [Parameter(Mandatory)] [string] $OutputPath
    )

    if (-not $PSCmdlet.ShouldProcess($OutputPath, 'Generate wiki pages')) {
        return
    }
    $null = New-Item -ItemType Directory -Path $OutputPath -Force
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $module = Import-Module -Name (Join-Path $SourceRoot 'Bylaw.psd1') -Force -PassThru -ErrorAction Stop
    $commands = @($module.ExportedFunctions.Keys | Sort-Object)
    $keywords = @(& $module { $script:BylawKeywordNames } | Sort-Object)

    # Commands: PlatyPS, as in the maintainer's other modules.
    $null = New-MarkdownHelp -Command $commands -OutputFolder $OutputPath -NoMetadata -Force -ErrorAction Stop
    foreach ($command in $commands) {
        $path = Join-Path $OutputPath "$command.md"
        $text = [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n"
        # PlatyPS 0.12 lists PowerShell 7.4's ProgressAction common parameter as the command's own.
        $text = $text -replace ' ?\[-ProgressAction <ActionPreference>\]', ''
        $text = $text -replace '(?s)### -ProgressAction\n.*?(?=\n### )', ''
        [System.IO.File]::WriteAllText($path, $text, $utf8NoBom)
    }

    # Keywords: private functions, so their help is read inside the module.
    $usage = Get-KeywordUsage -SourceRoot $SourceRoot
    foreach ($keyword in $keywords) {
        $help = & $module { param($Name) Get-Help -Name $Name -Full } $keyword
        $usedIn = if ($usage.ContainsKey($keyword)) { $usage[$keyword] } else { throw "No usage known for keyword '$keyword'. Add it to `$KeywordUsageFallback in build/Docs.ps1." }
        [System.IO.File]::WriteAllText((Join-Path $OutputPath "$keyword.md"), (ConvertTo-KeywordPage -Name $keyword -Help $help -UsedIn $usedIn), $utf8NoBom)
    }

    $sidebar = [System.Collections.Generic.List[string]]::new()
    $sidebar.Add('**[[Home]]**')
    $sidebar.Add('')
    $sidebar.Add('**Commands**')
    foreach ($command in $commands) { $sidebar.Add("* [[$command]]") }
    $sidebar.Add('')
    $sidebar.Add('**Keywords**')
    foreach ($keyword in $keywords) { $sidebar.Add("* [[$keyword]]") }
    [System.IO.File]::WriteAllText((Join-Path $OutputPath '_Sidebar.md'), (($sidebar -join "`n") + "`n"), $utf8NoBom)

    [string[]] (@($commands) + @($keywords) + '_Sidebar')
}

function Sync-WikiPageSet {
    # Copies the generated pages into a wiki clone. Removes pages the build generated last time but
    # not now, and refuses to replace a page it didn't generate, such as one written by hand.
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] [string] $GeneratedPath,
        [Parameter(Mandatory)] [string] $WikiPath
    )

    $listPath = Join-Path $WikiPath $script:GeneratedPagesFile
    $previous = if (Test-Path $listPath) { @(Get-Content -Path $listPath | Where-Object { $_ }) } else { @() }
    $pages = @(Get-ChildItem -Path $GeneratedPath -Filter '*.md' -File | ForEach-Object BaseName | Sort-Object)

    $conflicts = @($pages | Where-Object { $_ -notin $previous -and (Test-Path (Join-Path $WikiPath "$_.md")) })
    if ($conflicts.Count -gt 0) {
        throw "The wiki already has pages the build didn't generate: $($conflicts -join ', '). Rename or remove them in the wiki, so the build doesn't overwrite them."
    }
    foreach ($stale in @($previous | Where-Object { $_ -notin $pages })) {
        $stalePath = Join-Path $WikiPath "$stale.md"
        if ((Test-Path $stalePath) -and $PSCmdlet.ShouldProcess($stalePath, 'Remove page')) {
            Remove-Item -Path $stalePath
        }
    }
    if ($PSCmdlet.ShouldProcess($WikiPath, "Write $($pages.Count) pages")) {
        foreach ($page in $pages) {
            Copy-Item -Path (Join-Path $GeneratedPath "$page.md") -Destination (Join-Path $WikiPath "$page.md") -Force
        }
        [System.IO.File]::WriteAllText($listPath, (($pages -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
    }
    [string[]] $pages
}
