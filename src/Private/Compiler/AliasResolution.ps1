# Alias resolution pass (ADR-0008).
#
# Sets FieldRef.Resolved (and ResourceScope.ResolvedType) on the DSL layer of a policy and returns
# diagnostics. Rules, in order:
#   1. Reserved fields (name, type, location, tags['x'], ...) pass through; not inside Each.
#   2. A full alias (contains '/') is validated against the snapshot.
#   3. A short name under Resource '<type>' matches '<type>/<name>' exactly, else the unique alias of
#      that type ending in '/<name>' (some aliases are not prefixed with the full type path).
#   4. Inside Each, names are relative to the array alias; Element is the element itself.
#   5. Under Resource *, only reserved fields and full aliases are allowed.
#   6. [*] in a field outside Each is an error: negating it by swapping operators would be wrong.
#   7. Tag name is tags['name']; Tag (Param X) is [concat('tags[', parameters('x'), ']')] (ADR-0020).
#   8. Fields in Modify operations resolve as top-level fields (ADR-0024). So do Append fields,
#      which may also end in [*] (ADR-0029).
#   Value conditions (ADR-0025) test an expression and have no field to resolve.

$script:BylawReservedFields = @(
    'name', 'fullName', 'kind', 'type', 'location', 'id',
    'identity.type', 'identity.userAssignedIdentities',
    'extendedLocation', 'extendedLocation.name', 'extendedLocation.type',
    'tags'
)

function Invoke-BylawAliasResolution {
    [CmdletBinding()]
    [OutputType([BylawDiagnostic])]
    param(
        [Parameter(Mandatory)] [BylawPolicy] $Policy,
        [Parameter(Mandatory)] [BylawAliasSnapshot] $Snapshot,
        # Build-wide override: unknown aliases are allowed, each reported as a warning.
        [switch] $AllowUnknownAlias
    )

    $scope = $Policy.Resource
    if ($null -eq $scope) {
        return
    }

    $context = [pscustomobject]@{
        Policy            = $Policy
        Snapshot          = $Snapshot
        Type              = $null
        TypeKnown         = $false
        AnyType           = $scope.IsAnyType()
        AllowUnknownAlias = $AllowUnknownAlias.IsPresent
        Diagnostics       = [System.Collections.Generic.List[object]]::new()
    }

    if (-not $context.AnyType) {
        $canonicalType = $Snapshot.GetTypeName($scope.Type)
        if ($canonicalType) {
            $scope.ResolvedType = $canonicalType
            $context.Type = $canonicalType
            $context.TypeKnown = $true
        }
        else {
            $scope.ResolvedType = $scope.Type
            $context.Type = $scope.Type
            $severity = if ($context.AllowUnknownAlias) { [BylawSeverity]::Warning } else { [BylawSeverity]::Error }
            $context.Diagnostics.Add([BylawDiagnostic]::new($severity, 'BYL2003', (
                        "Resource type '$($scope.Type)' is not in the alias snapshot ($($Snapshot.Path)). " +
                        'Check the spelling, refresh the snapshot with Update-BylawAliasCache, or use -AllowUnknownAlias.'
                    ), $scope.Location))
        }
    }

    foreach ($applicability in $scope.When) {
        foreach ($child in $applicability.Children) {
            Resolve-BylawNodeAlias -Node $child -Context $context -ArrayAlias $null
        }
    }
    foreach ($requirement in $scope.Requirements) {
        foreach ($child in $requirement.Children) {
            Resolve-BylawNodeAlias -Node $child -Context $context -ArrayAlias $null
        }
    }
    # Modify operation fields resolve like top-level fields. A [*] field is left to validation,
    # which explains that Modify can't change array elements (ADR-0024).
    if ($Policy.Effect -is [BylawModify]) {
        foreach ($operation in $Policy.Effect.Operations) {
            if ($operation.Field.Kind -eq [BylawFieldKind]::Field -and $operation.Field.Name.Contains('[*]')) {
                continue
            }
            Resolve-BylawFieldAlias -Field $operation.Field -Context $context -ArrayAlias $null
        }
    }
    # Append fields resolve the same way, and may end in [*] to add an array element. A [*]
    # anywhere else is left to validation (ADR-0029).
    if ($Policy.Effect -is [BylawAppend]) {
        foreach ($operation in $Policy.Effect.Operations) {
            $field = $operation.Field
            $isArray = $field.Kind -eq [BylawFieldKind]::Field -and $field.Name.EndsWith('[*]')
            $inner = if ($isArray) { $field.Name.Substring(0, $field.Name.Length - 3) } else { $field.Name }
            if ($field.Kind -eq [BylawFieldKind]::Field -and $inner.Contains('[*]')) {
                continue
            }
            Resolve-BylawFieldAlias -Field $field -Context $context -ArrayAlias $null -IsArrayPath:$isArray
        }
    }

    $context.Diagnostics
}

function Resolve-BylawNodeAlias {
    param(
        [Parameter(Mandatory)] [BylawNode] $Node,
        [Parameter(Mandatory)] [pscustomobject] $Context,
        [AllowNull()] [string] $ArrayAlias
    )

    if ($Node -is [BylawAssertion]) {
        # A value condition tests an expression, so it has no field to resolve (ADR-0025).
        if ($null -ne $Node.Field) {
            Resolve-BylawFieldAlias -Field $Node.Field -Context $Context -ArrayAlias $ArrayAlias
        }
        return
    }
    if ($Node -is [BylawConditionGroup]) {
        # A group doesn't change the scope: fields resolve as they would outside it.
        foreach ($child in $Node.Children) {
            Resolve-BylawNodeAlias -Node $child -Context $Context -ArrayAlias $ArrayAlias
        }
        return
    }
    if ($Node -is [BylawEach]) {
        $resolved = Resolve-BylawFieldAlias -Field $Node.Field -Context $Context -ArrayAlias $ArrayAlias -IsArrayPath -PassThru
        if (-not $resolved) {
            # The array itself didn't resolve; its children would only repeat the error.
            return
        }
        foreach ($child in $Node.Children) {
            Resolve-BylawNodeAlias -Node $child -Context $Context -ArrayAlias $resolved
        }
    }
}

function Resolve-BylawFieldAlias {
    # Resolves one field reference in place. With -PassThru, returns the resolved name ('' on error).
    param(
        [Parameter(Mandatory)] [BylawFieldRef] $Field,
        [Parameter(Mandatory)] [pscustomobject] $Context,
        [AllowNull()] [string] $ArrayAlias,
        [switch] $IsArrayPath,
        [switch] $PassThru
    )

    $resolved = Get-BylawResolvedAlias -Field $Field -Context $Context -ArrayAlias $ArrayAlias -IsArrayPath:$IsArrayPath
    if ($resolved) {
        $Field.Resolved = $resolved
    }
    if ($PassThru) {
        $resolved
    }
}

function Get-BylawResolvedAlias {
    param(
        [Parameter(Mandatory)] [BylawFieldRef] $Field,
        [Parameter(Mandatory)] [pscustomobject] $Context,
        [AllowNull()] [string] $ArrayAlias,
        [switch] $IsArrayPath
    )

    $snapshot = $Context.Snapshot
    $location = $Field.Location

    if ($Field.Kind -eq [BylawFieldKind]::Element) {
        return $ArrayAlias
    }
    if ($Field.Kind -eq [BylawFieldKind]::Tag) {
        return Get-BylawTagFieldName -Field $Field -Policy $Context.Policy
    }

    $name = $Field.Name
    $withoutOwnArray = if ($IsArrayPath) { $name.Substring(0, $name.Length - 3) } else { $name }
    if ($withoutOwnArray.Contains('[*]')) {
        $hint = if ($IsArrayPath) {
            'Nest one Each per array level instead.'
        }
        else {
            "Wrap it in Each, e.g. Each $($name.Substring(0, $name.IndexOf('[*]') + 3)) { Field $($name.Substring($name.IndexOf('[*]') + 3).TrimStart('.')) | Must ... }."
        }
        Add-BylawResolutionDiagnostic -Context $Context -Code 'BYL2005' -Location $location -Message (
            "Field '$name' uses [*] outside Each. Azure evaluates a [*] field condition for every element, so it can't be inverted safely. $hint"
        )
        return ''
    }

    # Inside Each: relative to the array alias.
    if ($ArrayAlias) {
        $candidate = "$ArrayAlias.$name"
        $canonical = $snapshot.FindAlias($candidate)
        if ($canonical) {
            return $canonical
        }
        $prefix = "$ArrayAlias."
        $elementNames = @($snapshot.GetAliases($Context.Type).Values | Where-Object {
                $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -and -not $_.Substring($prefix.Length).Contains('[*]')
            } | ForEach-Object { $_.Substring($prefix.Length) })
        return Resolve-BylawUnknownAlias -Field $Field -Context $Context -Candidate $candidate -Suggestions $elementNames -Description "Element field '$name' of '$ArrayAlias'"
    }

    # Reserved fields.
    $reserved = Get-BylawReservedField -Name $name
    if ($reserved) {
        return $reserved
    }

    # Full alias.
    if ($name.Contains('/')) {
        $canonical = $snapshot.FindAlias($name)
        if ($canonical) {
            return $canonical
        }
        $typeAliases = if ($Context.TypeKnown) { @($snapshot.GetAliases($Context.Type).Values) } else { @() }
        return Resolve-BylawUnknownAlias -Field $Field -Context $Context -Candidate $name -Suggestions $typeAliases -Description "Alias '$name'"
    }

    # Short name.
    if ($Context.AnyType) {
        Add-BylawResolutionDiagnostic -Context $Context -Code 'BYL2004' -Location $location -Message (
            "Field '$name' needs a full alias under Resource *, because there is no resource type to resolve it against (e.g. 'Microsoft.Storage/storageAccounts/$name')."
        )
        return ''
    }
    if (-not $Context.TypeKnown) {
        # The unknown type was already reported once; only build names if unknown aliases are allowed.
        if ($Context.AllowUnknownAlias -or $Field.AllowUnknownAlias) {
            return "$($Context.Type)/$name"
        }
        return ''
    }

    $aliases = $snapshot.GetAliases($Context.Type)
    $exact = "$($Context.Type)/$name"
    $canonical = $null
    if ($aliases.TryGetValue($exact, [ref] $canonical)) {
        return $canonical
    }
    $suffix = "/$name"
    $suffixMatches = @($aliases.Values | Where-Object { $_.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($suffixMatches.Count -eq 1) {
        return $suffixMatches[0]
    }
    if ($suffixMatches.Count -gt 1) {
        Add-BylawResolutionDiagnostic -Context $Context -Code 'BYL2002' -Location $location -Message (
            "Field '$name' matches more than one alias of '$($Context.Type)': $(($suffixMatches | Sort-Object) -join ', '). Use the full alias."
        )
        return ''
    }

    $shortNames = @($aliases.Values | Where-Object { -not $_.Contains('[*]') } | ForEach-Object {
            if ($_.StartsWith("$($Context.Type)/", [System.StringComparison]::OrdinalIgnoreCase)) { $_.Substring($Context.Type.Length + 1) } else { $_.Substring($_.LastIndexOf('/') + 1) }
        })
    Resolve-BylawUnknownAlias -Field $Field -Context $Context -Candidate $exact -Suggestions $shortNames -Description "Field '$name' of '$($Context.Type)'"
}

function Resolve-BylawUnknownAlias {
    # An alias that isn't in the snapshot: allowed by override (per field, or build-wide with a
    # warning), otherwise an error with the closest known names.
    param(
        [Parameter(Mandatory)] [BylawFieldRef] $Field,
        [Parameter(Mandatory)] [pscustomobject] $Context,
        [Parameter(Mandatory)] [string] $Candidate,
        [AllowEmptyCollection()] [string[]] $Suggestions = @(),
        [Parameter(Mandatory)] [string] $Description
    )

    if ($Field.AllowUnknownAlias) {
        return $Candidate
    }
    if ($Context.AllowUnknownAlias) {
        Add-BylawResolutionDiagnostic -Context $Context -Code 'BYL2006' -Severity Warning -Location $Field.Location -Message (
            "$Description is not in the alias snapshot; using '$Candidate' because -AllowUnknownAlias is set."
        )
        return $Candidate
    }

    $hint = ''
    if ($Suggestions.Count -gt 0) {
        $closest = Get-BylawClosestMatch -Value $Field.Name -Candidates $Suggestions
        if ($closest) {
            $hint = " Did you mean '$closest'?"
        }
    }
    Add-BylawResolutionDiagnostic -Context $Context -Code 'BYL2001' -Location $Field.Location -Message (
        "$Description is not in the alias snapshot.$hint Use Field <name> -AllowUnknownAlias if the alias is newer than the snapshot, or refresh it with Update-BylawAliasCache."
    )
    ''
}

function Get-BylawTagFieldName {
    # The field name for Tag (ADR-0020): tags['name'], or for a parameter the form Azure's built-in
    # tag policies use, [concat('tags[', parameters('tagName'), ']')]. An undeclared parameter
    # gives '', and validation reports it.
    param([Parameter(Mandatory)] [BylawFieldRef] $Field, [Parameter(Mandatory)] [BylawPolicy] $Policy)

    if ($Field.TagName -isnot [BylawParamRef]) {
        return "tags['$($Field.TagName.Value)']"
    }
    $parameter = $Policy.FindParameter($Field.TagName.Name)
    if ($null -eq $parameter) {
        return ''
    }
    $jsonName = Get-BylawParameterJsonName -Name $parameter.Name -JsonName $parameter.JsonName
    "[concat('tags[', parameters('$jsonName'), ']')]"
}

function Get-BylawReservedField {
    # Canonical reserved field name, or '' when Name is not a reserved field.
    param([Parameter(Mandatory)] [string] $Name)

    foreach ($reserved in $script:BylawReservedFields) {
        if ([string]::Equals($reserved, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $reserved
        }
    }
    # tags['name'], tags[name] and tags.name keep the tag name exactly as written.
    if ($Name -match '^(?i:tags)(?<rest>\[.+\]|\..+)$') {
        return 'tags' + $Matches.rest
    }
    ''
}

function Add-BylawResolutionDiagnostic {
    param(
        [Parameter(Mandatory)] [pscustomobject] $Context,
        [Parameter(Mandatory)] [string] $Code,
        [Parameter(Mandatory)] [string] $Message,
        [BylawSourceLocation] $Location,
        [BylawSeverity] $Severity = [BylawSeverity]::Error
    )
    $Context.Diagnostics.Add([BylawDiagnostic]::new($Severity, $Code, $Message, $Location))
}
