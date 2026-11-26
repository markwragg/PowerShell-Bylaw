function ConvertFrom-BylawJson {
    # Parses JSON with System.Text.Json into ordered dictionaries, object arrays and primitives.
    #
    # Used instead of ConvertFrom-Json because ConvertFrom-Json turns ISO date strings (such as an
    # alias snapshot's generatedAt) into DateTime values, and only PowerShell 7.5+ can turn that off.
    # Strings stay strings, objects keep the file's key order, and duplicate keys are an error.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Json
    )

    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth = 128
    $document = [System.Text.Json.JsonDocument]::Parse($Json, $options)
    try {
        ConvertFrom-BylawJsonElement -Element $document.RootElement
    }
    finally {
        $document.Dispose()
    }
}

function ConvertFrom-BylawJsonElement {
    param([Parameter(Mandatory)] [System.Text.Json.JsonElement] $Element)

    switch ($Element.ValueKind) {
        'Object' {
            $result = [ordered]@{}
            foreach ($property in $Element.EnumerateObject()) {
                if ($result.Contains($property.Name)) {
                    throw [System.FormatException]::new("Duplicate JSON key '$($property.Name)'.")
                }
                $result[$property.Name] = ConvertFrom-BylawJsonElement -Element $property.Value
            }
            return $result
        }
        'Array' {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $Element.EnumerateArray()) {
                $items.Add((ConvertFrom-BylawJsonElement -Element $item))
            }
            return , $items.ToArray()
        }
        'String' { return $Element.GetString() }
        'Number' {
            $long = 0L
            if ($Element.TryGetInt64([ref] $long)) {
                return $long
            }
            return $Element.GetDouble()
        }
        'True' { return $true }
        'False' { return $false }
        default { return $null }
    }
}
