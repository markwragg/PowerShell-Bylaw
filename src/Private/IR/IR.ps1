# Bylaw intermediate representation (ADR-0006).
#
# All IR classes live in this one file because PowerShell classes that reference each other must be
# parsed together. Two layers:
#
#   DSL layer     - what the keywords produce, exactly as written: BylawAssertion (Must), BylawEach,
#                   BylawRequirement, BylawResourceScope. Lossless, so the decompiler can target it.
#   Policy layer  - Azure Policy conditions: BylawFieldCondition, BylawValueCondition,
#                   BylawCountCondition, BylawGroup, BylawNot. Produced by the compiler passes from
#                   the DSL layer, or directly by the decompiler from JSON.
#
# Every node carries a BylawSourceLocation so any pass can report file, line and keyword.

enum BylawSeverity {
    Error
    Warning
}

enum BylawGroupKind {
    AllOf
    AnyOf
}

enum BylawMissingMode {
    # Strict at top level, lenient inside Each (ADR-0004).
    Default
    IfPresent
    Strict
}

enum BylawFieldKind {
    # A named field or alias: Field name.
    Field
    # The current element of a primitive array inside Each.
    Element
}

class BylawSourceLocation {
    [string] $File
    [int] $Line
    [int] $Column
    [string] $Keyword

    BylawSourceLocation() {}

    BylawSourceLocation([string] $file, [int] $line, [int] $column, [string] $keyword) {
        $this.File = $file
        $this.Line = $line
        $this.Column = $column
        $this.Keyword = $keyword
    }

    static [BylawSourceLocation] FromInvocation([System.Management.Automation.InvocationInfo] $invocation, [string] $keyword) {
        if ($null -eq $invocation) {
            return [BylawSourceLocation]::new($null, 0, 0, $keyword)
        }
        return [BylawSourceLocation]::new($invocation.ScriptName, $invocation.ScriptLineNumber, $invocation.OffsetInLine, $keyword)
    }

    [string] ToString() {
        $place = if ($this.File) { $this.File } else { '<unknown>' }
        if ($this.Line -gt 0) {
            $place = '{0}:{1}' -f $place, $this.Line
        }
        if ($this.Keyword) {
            return '{0} [{1}]' -f $place, $this.Keyword
        }
        return $place
    }
}

class BylawNode {
    [BylawSourceLocation] $Location
}

#region Values

class BylawValue : BylawNode {
}

class BylawLiteral : BylawValue {
    # string, number, boolean, array or (ordered) dictionary.
    [object] $Value

    BylawLiteral() {}

    BylawLiteral([object] $value) {
        $this.Value = $value
    }

    [string] ToString() {
        return [string] $this.Value
    }
}

class BylawParamRef : BylawValue {
    # Parameter name as declared in the DSL (not the emitted JSON name, see ADR-0018).
    [string] $Name

    BylawParamRef() {}

    BylawParamRef([string] $name) {
        $this.Name = $name
    }

    [string] ToString() {
        return 'Param {0}' -f $this.Name
    }
}

class BylawExpr : BylawValue {
    # Raw ARM template expression, preserved verbatim, e.g. "[field('location')]".
    [string] $Text

    BylawExpr() {}

    BylawExpr([string] $text) {
        $this.Text = $text
    }

    [string] ToString() {
        return $this.Text
    }
}

#endregion

#region Fields

class BylawFieldRef : BylawNode {
    [BylawFieldKind] $Kind = [BylawFieldKind]::Field
    # As written by the author, e.g. 'publicNetworkAccess' or 'value' inside Each.
    [string] $Name
    # Full alias or reserved field name, set by the alias resolution pass.
    [string] $Resolved
    [bool] $AllowUnknownAlias

    BylawFieldRef() {}

    BylawFieldRef([string] $name) {
        $this.Name = $name
    }

    [string] ToString() {
        if ($this.Kind -eq [BylawFieldKind]::Element) {
            return 'Element'
        }
        if ($this.Resolved) {
            return $this.Resolved
        }
        return $this.Name
    }
}

#endregion

#region Policy layer (Azure Policy conditions)

class BylawOperator {
    # Every Azure Policy condition operator Bylaw can represent.
    static [string[]] $All = @(
        'equals', 'notEquals',
        'like', 'notLike',
        'match', 'notMatch',
        'matchInsensitively', 'notMatchInsensitively',
        'contains', 'notContains',
        'in', 'notIn',
        'containsKey', 'notContainsKey',
        'less', 'lessOrEquals',
        'greater', 'greaterOrEquals',
        'exists'
    )

    static [bool] IsValid([string] $operator) {
        # Azure operator names are case-insensitive; Bylaw always emits the canonical casing.
        return -not [string]::IsNullOrEmpty([BylawOperator]::Canonical($operator))
    }

    # Returns '' (not $null: [string] methods coerce $null to '') when the operator is unknown.
    static [string] Canonical([string] $operator) {
        foreach ($candidate in [BylawOperator]::All) {
            if ([string]::Equals($candidate, $operator, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $candidate
            }
        }
        return $null
    }
}

class BylawCondition : BylawNode {
    # Provenance: the DSL node (assertion, requirement, When block) this condition was compiled
    # from, or $null for conditions read from JSON.
    [BylawNode] $Origin
}

class BylawFieldCondition : BylawCondition {
    [BylawFieldRef] $Field
    [string] $Operator
    [BylawValue] $Value

    BylawFieldCondition() {}

    BylawFieldCondition([BylawFieldRef] $field, [string] $operator, [BylawValue] $value) {
        $canonical = [BylawOperator]::Canonical($operator)
        if ([string]::IsNullOrEmpty($canonical)) {
            throw [System.ArgumentException]::new("Unknown policy operator '$operator'.", 'operator')
        }
        $this.Field = $field
        $this.Operator = $canonical
        $this.Value = $value
    }

    [string] ToString() {
        return '{0} {1} {2}' -f $this.Field, $this.Operator, $this.Value
    }
}

class BylawValueCondition : BylawCondition {
    # A "value" condition: the left-hand side is an expression rather than a field.
    [BylawValue] $Subject
    [string] $Operator
    [BylawValue] $Value

    BylawValueCondition() {}

    BylawValueCondition([BylawValue] $subject, [string] $operator, [BylawValue] $value) {
        $canonical = [BylawOperator]::Canonical($operator)
        if ([string]::IsNullOrEmpty($canonical)) {
            throw [System.ArgumentException]::new("Unknown policy operator '$operator'.", 'operator')
        }
        $this.Subject = $subject
        $this.Operator = $canonical
        $this.Value = $value
    }
}

class BylawCountCondition : BylawCondition {
    # Field count: Field is a [*] alias. Value count (decompiler/later): ValueSource and Name.
    [BylawFieldRef] $Field
    [BylawValue] $ValueSource
    [string] $Name
    # Optional filter; $null counts every element.
    [BylawCondition] $Where
    [string] $Operator
    [BylawValue] $Value

    BylawCountCondition() {}

    BylawCountCondition([BylawFieldRef] $field, [BylawCondition] $where, [string] $operator, [BylawValue] $value) {
        $canonical = [BylawOperator]::Canonical($operator)
        if ([string]::IsNullOrEmpty($canonical)) {
            throw [System.ArgumentException]::new("Unknown policy operator '$operator'.", 'operator')
        }
        $this.Field = $field
        $this.Where = $where
        $this.Operator = $canonical
        $this.Value = $value
    }
}

class BylawGroup : BylawCondition {
    [BylawGroupKind] $Kind
    [System.Collections.Generic.List[BylawCondition]] $Children = [System.Collections.Generic.List[BylawCondition]]::new()

    BylawGroup() {}

    BylawGroup([BylawGroupKind] $kind) {
        $this.Kind = $kind
    }

    BylawGroup([BylawGroupKind] $kind, [BylawCondition[]] $children) {
        $this.Kind = $kind
        foreach ($child in $children) {
            $this.Children.Add($child)
        }
    }

    [string] ToString() {
        return '{0}[{1}]' -f $this.Kind, $this.Children.Count
    }
}

class BylawNot : BylawCondition {
    # Never produced by the compiler in language version 1.0 (ADR-0002); kept for the decompiler.
    [BylawCondition] $Child

    BylawNot() {}

    BylawNot([BylawCondition] $child) {
        $this.Child = $child
    }
}

class BylawEffect : BylawNode {
    # Literal effect name or a BylawParamRef.
    [BylawValue] $Value
    # The 'details' block for effects that need one (Modify in Milestone 2); $null otherwise.
    [System.Collections.Specialized.OrderedDictionary] $Details

    BylawEffect() {}

    BylawEffect([BylawValue] $value) {
        $this.Value = $value
    }
}

class BylawPolicyRule : BylawNode {
    [BylawCondition] $If
    [BylawEffect] $Then

    BylawPolicyRule() {}

    BylawPolicyRule([BylawCondition] $if, [BylawEffect] $then) {
        $this.If = $if
        $this.Then = $then
    }
}

#endregion

#region DSL layer (as written)

class BylawAssertion : BylawNode {
    # One Must statement, before inversion.
    [BylawFieldRef] $Field
    # DSL operator as written, without the dash, e.g. 'Be', 'BeIn', 'Exist'.
    [string] $DslOperator
    # The non-negated Azure operator it maps to, e.g. 'equals' for -Be (ADR-0015).
    [string] $Operator
    # $null for -Exist.
    [BylawValue] $Value
    [bool] $Negated
    [BylawMissingMode] $MissingMode = [BylawMissingMode]::Default

    BylawAssertion() {}

    [string] ToString() {
        $parts = [System.Collections.Generic.List[string]]::new()
        $parts.Add([string] $this.Field)
        $parts.Add('| Must')
        if ($this.Negated) {
            $parts.Add('-Not')
        }
        $parts.Add('-' + $this.DslOperator)
        if ($null -ne $this.Value) {
            $parts.Add([string] $this.Value)
        }
        if ($this.MissingMode -ne [BylawMissingMode]::Default) {
            $parts.Add('-' + $this.MissingMode)
        }
        return $parts -join ' '
    }
}

class BylawEach : BylawNode {
    # The [*] array path as written, e.g. 'networkAcls.ipRules[*]'.
    [BylawFieldRef] $Field
    # BylawAssertion and nested BylawEach nodes, in source order.
    [System.Collections.Generic.List[BylawNode]] $Children = [System.Collections.Generic.List[BylawNode]]::new()

    BylawEach() {}

    BylawEach([BylawFieldRef] $field) {
        $this.Field = $field
    }
}

class BylawRequirement : BylawNode {
    [string] $Description
    # BylawAssertion and BylawEach nodes, in source order.
    [System.Collections.Generic.List[BylawNode]] $Children = [System.Collections.Generic.List[BylawNode]]::new()

    BylawRequirement() {}

    BylawRequirement([string] $description) {
        $this.Description = $description
    }
}

class BylawApplicability : BylawNode {
    # One When block. Its assertions are emitted as written, not inverted (ADR-0002).
    [System.Collections.Generic.List[BylawNode]] $Children = [System.Collections.Generic.List[BylawNode]]::new()
}

class BylawResourceScope : BylawNode {
    # Resource type as written, or '*' for no type condition.
    [string] $Type
    # Type in the alias snapshot's casing, set by the alias resolution pass.
    [string] $ResolvedType
    [System.Collections.Generic.List[BylawApplicability]] $When = [System.Collections.Generic.List[BylawApplicability]]::new()
    [System.Collections.Generic.List[BylawRequirement]] $Requirements = [System.Collections.Generic.List[BylawRequirement]]::new()

    BylawResourceScope() {}

    BylawResourceScope([string] $type) {
        $this.Type = $type
    }

    [bool] IsAnyType() {
        return $this.Type -eq '*'
    }
}

class BylawProperties : BylawNode {
    [string] $DisplayName
    [string] $Description
    [string] $Mode
    [string] $Version
    [string] $Category
    [System.Nullable[bool]] $Preview
    [System.Nullable[bool]] $Deprecated
    # User metadata merged into 'metadata' (ADR-0016).
    [System.Collections.IDictionary] $Metadata
}

class BylawParameter : BylawNode {
    # DSL name, e.g. 'Effect'.
    [string] $Name
    # Explicit emitted name override (ADR-0018); $null means derive it.
    [string] $JsonName
    # Azure parameter type: String, Array, Object, Boolean, Integer, Float or DateTime.
    [string] $Type
    [string] $DisplayName
    [string] $Description
    [object[]] $AllowedValues
    [object] $DefaultValue
    [bool] $HasDefault
    # Additional parameter metadata (e.g. strongType), from the hashtable form.
    [System.Collections.IDictionary] $Metadata

    BylawParameter() {}

    BylawParameter([string] $name) {
        $this.Name = $name
    }
}

class BylawPolicy : BylawNode {
    # Definition name, exactly as given to Policy 'name' (ADR-0010).
    [string] $Name
    [BylawProperties] $Properties
    [System.Collections.Generic.List[BylawParameter]] $Parameters = [System.Collections.Generic.List[BylawParameter]]::new()
    [BylawResourceScope] $Resource
    [BylawEffect] $Effect
    # Policy-layer rule. Set by the compiler from Resource/Effect, or by the decompiler from JSON.
    [BylawPolicyRule] $Rule

    BylawPolicy() {}

    BylawPolicy([string] $name) {
        $this.Name = $name
    }

    [BylawParameter] FindParameter([string] $name) {
        foreach ($parameter in $this.Parameters) {
            if ([string]::Equals($parameter.Name, $name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $parameter
            }
        }
        return $null
    }
}

#endregion

#region Alias snapshot (ADR-0008)

class BylawAliasSnapshot {
    # Where the snapshot was loaded from, for diagnostics.
    [string] $Path
    [string] $GeneratedAt

    # Type name -> alias names, from Read-BylawAliasSnapshotData.
    hidden [System.Collections.IDictionary] $Types
    # Case-insensitive indexes, built lazily so a full snapshot only pays for the types a build uses.
    hidden [System.Collections.Generic.Dictionary[string, string]] $TypeNames
    hidden [System.Collections.Generic.Dictionary[string, System.Collections.Generic.Dictionary[string, string]]] $TypeIndex
    hidden [System.Collections.Generic.Dictionary[string, string]] $GlobalIndex

    BylawAliasSnapshot([string] $path, [string] $generatedAt, [System.Collections.IDictionary] $types) {
        $this.Path = $path
        $this.GeneratedAt = $generatedAt
        $this.Types = $types
        $this.TypeNames = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in $types.Keys) {
            $this.TypeNames[$name] = $name
        }
        $this.TypeIndex = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.Dictionary[string, string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    # Canonical type name, or '' when the type is not in the snapshot.
    [string] GetTypeName([string] $type) {
        $canonical = $null
        if ($this.TypeNames.TryGetValue($type, [ref] $canonical)) {
            return $canonical
        }
        return ''
    }

    # Case-insensitive map of alias name -> canonical alias name for one type (empty if unknown).
    [System.Collections.Generic.Dictionary[string, string]] GetAliases([string] $type) {
        $canonicalType = $this.GetTypeName($type)
        $index = $null
        if ($canonicalType -and $this.TypeIndex.TryGetValue($canonicalType, [ref] $index)) {
            return $index
        }
        $index = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($canonicalType) {
            foreach ($alias in $this.Types[$canonicalType]) {
                $index[$alias] = $alias
            }
            $this.TypeIndex[$canonicalType] = $index
        }
        return $index
    }

    # Canonical alias name for a full alias of any type, or '' when it is not in the snapshot.
    [string] FindAlias([string] $alias) {
        if ($null -eq $this.GlobalIndex) {
            $this.GlobalIndex = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($type in $this.Types.Keys) {
                foreach ($entry in $this.GetAliases($type).GetEnumerator()) {
                    $this.GlobalIndex[$entry.Key] = $entry.Value
                }
            }
        }
        $canonical = $null
        if ($this.GlobalIndex.TryGetValue($alias, [ref] $canonical)) {
            return $canonical
        }
        return ''
    }
}

#endregion

#region Front-end state

class BylawFrame {
    # One open keyword block (Policy, Resource, When, Require, Each) while the DSL runs.
    [string] $Keyword
    [BylawNode] $Node
    # Field references produced in this block that no Must has consumed yet.
    [System.Collections.Generic.List[BylawFieldRef]] $PendingFields = [System.Collections.Generic.List[BylawFieldRef]]::new()
    # Keywords that may appear at most once in this block, and where they first appeared.
    [hashtable] $Singletons = @{}

    BylawFrame([string] $keyword, [BylawNode] $node) {
        $this.Keyword = $keyword
        $this.Node = $node
    }
}

#endregion

#region Diagnostics

class BylawDiagnostic {
    [BylawSeverity] $Severity
    # Stable identifier, e.g. 'BYL1001', so tests and users can match on it.
    [string] $Code
    [string] $Message
    [BylawSourceLocation] $Location

    BylawDiagnostic() {}

    BylawDiagnostic([BylawSeverity] $severity, [string] $code, [string] $message, [BylawSourceLocation] $location) {
        $this.Severity = $severity
        $this.Code = $code
        $this.Message = $message
        $this.Location = $location
    }

    [string] ToString() {
        # file:line [Keyword] CODE: message
        $where = if ($this.Location) { $this.Location.ToString() } else { '<unknown>' }
        return '{0} {1}: {2}' -f $where, $this.Code, $this.Message
    }
}

class BylawCompileException : System.Exception {
    [BylawDiagnostic[]] $Diagnostics

    BylawCompileException([BylawDiagnostic[]] $diagnostics) : base([BylawCompileException]::FormatMessage($diagnostics)) {
        $this.Diagnostics = $diagnostics
    }

    hidden static [string] FormatMessage([BylawDiagnostic[]] $diagnostics) {
        $lines = foreach ($diagnostic in $diagnostics) {
            $diagnostic.ToString()
        }
        # LF on every OS, so messages are identical in CI logs and tests.
        return ($lines -join "`n")
    }
}

#endregion
