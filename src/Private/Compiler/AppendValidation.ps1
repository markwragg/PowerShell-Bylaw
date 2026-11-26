# Validation of Append blocks (ADR-0029). Called by Invoke-BylawValidation after alias resolution.

function Test-BylawAppend {
    param(
        [Parameter(Mandatory)] [BylawAppend] $Append,
        [Parameter(Mandatory)] [BylawPolicy] $Policy,
        [Parameter(Mandatory)] [scriptblock] $Add
    )

    $checked = Get-BylawRequirementFieldName -Scope $Policy.Resource
    $seen = @{}

    foreach ($operation in $Append.Operations) {
        $field = $operation.Field
        $location = $operation.Location
        Test-BylawModifyParameter -Operation $operation -Policy $Policy -Add $Add

        $isArray = $field.Kind -eq [BylawFieldKind]::Field -and $field.Name.EndsWith('[*]')
        $inner = if ($isArray) { $field.Name.Substring(0, $field.Name.Length - 3) } else { $field.Name }
        if ($field.Kind -eq [BylawFieldKind]::Field -and $inner.Contains('[*]')) {
            $outer = $field.Name.Substring(0, $field.Name.IndexOf('[*]') + 3)
            & $Add 'BYL3080' "Append can't add to '$($field.Name)': [*] is only allowed at the end of the path, to add an element to an array, e.g. Field '$outer' | Add @{ ... }." $location
            continue
        }
        $name = $field.Resolved
        if (-not $name) {
            # Alias resolution already reported it.
            continue
        }

        $key = $name.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            & $Add 'BYL3081' "'$name' is added by more than one Add (first at line $($seen[$key].Line)). Use one Add per field; to add several array elements, add an array." $location
            continue
        }
        $seen[$key] = $location

        if ($field.Kind -eq [BylawFieldKind]::Tag -or $name -match '^tags(\[|\.|$)') {
            & $Add 'BYL3082' "Append adds the tag '$name'. Azure recommends Modify for tags: Modify -Role 'Tag Contributor' { Tag ... | Add ... } (ADR-0024)." $location ([BylawSeverity]::Warning)
        }

        $isChecked = $checked.Contains($name) -or ($isArray -and @($checked | Where-Object { $_.StartsWith("$name.", [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0)
        if (-not $isChecked) {
            & $Add 'BYL3083' "Append adds '$name', but no Require checks it, so existing resources are reported as non-compliant whatever their value. Add a Require for '$name'." $location ([BylawSeverity]::Warning)
        }
    }
}
