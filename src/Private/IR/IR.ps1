# Bylaw intermediate representation (ADR-0006).
#
# All IR classes live in this one file because PowerShell classes that reference each other must be
# parsed together. Two layers:
#
#   DSL layer     - what the keywords produce, exactly as written: BylawAssertion (Must), BylawEach,
#                   BylawConditionGroup (AnyOf, AllOf), BylawRequirement, BylawResourceScope.
#                   Lossless, so the decompiler can target it.
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
    # A tag: Tag name. FieldRef.TagName holds the name or a Param reference (ADR-0020).
    Tag
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

class BylawResourceGroupTag : BylawValue {
    # The resource group's tag value: [resourceGroup().tags['name']] (ADR-0020). TagName is a
    # BylawLiteral string or a BylawParamRef.
    [BylawValue] $TagName

    BylawResourceGroupTag() {}

    BylawResourceGroupTag([BylawValue] $tagName) {
        $this.TagName = $tagName
    }

    [string] ToString() {
        if ($this.TagName -is [BylawParamRef]) {
            return 'ResourceGroupTag ({0})' -f $this.TagName
        }
        return 'ResourceGroupTag {0}' -f $this.TagName
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
    # For Kind Tag: the tag name as a BylawLiteral string, or a BylawParamRef.
    [BylawValue] $TagName

    BylawFieldRef() {}

    BylawFieldRef([string] $name) {
        $this.Name = $name
    }

    [string] ToString() {
        if ($this.Kind -eq [BylawFieldKind]::Element) {
            return 'Element'
        }
        if ($this.Kind -eq [BylawFieldKind]::Tag -and $this.TagName -is [BylawParamRef]) {
            return 'Tag ({0})' -f $this.TagName
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
    [System.Collections.Generic.List[object]] $Children = [System.Collections.Generic.List[object]]::new()

    BylawGroup() {}

    BylawGroup([BylawGroupKind] $kind) {
        $this.Kind = $kind
    }

    BylawGroup([BylawGroupKind] $kind, [object[]] $children) {
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
    # Literal effect name, a BylawParamRef or a BylawExpr.
    [BylawValue] $Value

    BylawEffect() {}

    BylawEffect([BylawValue] $value) {
        $this.Value = $value
    }
}

class BylawModifyOperation : BylawNode {
    # One operation in a Modify block (ADR-0024): Field | AddOrReplace v, | Add v or | Remove.
    # Operation is the emitted name: 'addOrReplace', 'add' or 'remove'.
    [string] $Operation
    [BylawFieldRef] $Field
    # $null for remove.
    [BylawValue] $Value
    # The operation's optional condition, an Arm expression.
    [BylawExpr] $Condition

    BylawModifyOperation() {}

    BylawModifyOperation([string] $operation, [BylawFieldRef] $field) {
        $this.Operation = $operation
        $this.Field = $field
    }

    [string] ToString() {
        return '{0} {1}' -f $this.Field, $this.Operation
    }
}

class BylawModify : BylawEffect {
    # Modify -Role ... { operations } (ADR-0024). Value is the literal 'Modify', or the -Effect
    # parameter or expression.
    # -Role values as written (ADR-0022).
    [string[]] $Roles = @()
    # Full role definition IDs, in the order written, set by the validation pass.
    [string[]] $RoleDefinitionIds = @()
    # 'audit', 'deny' or 'disabled' as emitted, or $null when not set.
    [string] $ConflictEffect
    [System.Collections.Generic.List[object]] $Operations = [System.Collections.Generic.List[object]]::new()

    BylawModify() {}

    BylawModify([BylawValue] $value) : base($value) {}
}

class BylawAppend : BylawEffect {
    # Append { Field x | Add v } (ADR-0029). Value is the literal 'Append', or the -Effect parameter
    # or expression. Operations are BylawModifyOperation objects with Operation 'add' and no
    # Condition, in the order written.
    [System.Collections.Generic.List[object]] $Operations = [System.Collections.Generic.List[object]]::new()

    BylawAppend() {}

    BylawAppend([BylawValue] $value) : base($value) {}
}

class BylawIfNotExists : BylawEffect {
    # Shared by AuditIfNotExists and DeployIfNotExists (ADR-0030): the related resource, and the
    # Require blocks that describe its compliant state.
    # -Type as written, and in the alias snapshot's casing (set by alias resolution).
    [string] $Type
    [string] $ResolvedType
    # -Name and -ResourceGroupName: literals, Param or Arm, or $null when not set.
    [BylawValue] $Name
    [BylawValue] $ResourceGroupName
    # 'ResourceGroup' or 'Subscription' as emitted, or $null when not set.
    [string] $ExistenceScope
    # As written, e.g. 'AfterProvisioning' or 'PT30M', or $null when not set.
    [string] $EvaluationDelay
    # BylawRequirement nodes, in source order. Fields resolve against Type.
    [System.Collections.Generic.List[object]] $Requirements = [System.Collections.Generic.List[object]]::new()
    # The compliant existence condition, set by the inversion pass. $null without Require blocks.
    [BylawCondition] $ExistenceCondition

    BylawIfNotExists() {}

    BylawIfNotExists([BylawValue] $value) : base($value) {}
}

class BylawAuditIfNotExists : BylawIfNotExists {
    # AuditIfNotExists -Type ... { Require ... } (ADR-0030). Value is the literal
    # 'AuditIfNotExists', or the -Effect parameter or expression.

    BylawAuditIfNotExists() {}

    BylawAuditIfNotExists([BylawValue] $value) : base($value) {}
}

class BylawDeployment : BylawNode {
    # Deployment -TemplateFile ... | -Template @{ } [-Parameters @{ }] [-Scope] [-Location]
    # (ADR-0031). The mode is always incremental.
    # The template as ordered dictionaries, arrays and primitives, in its own key order.
    [object] $Template
    # The template file's full path, or $null for -Template.
    [string] $TemplateFile
    # Template parameter name -> BylawValue, in the order written.
    [System.Collections.Specialized.OrderedDictionary] $Parameters = [System.Collections.Specialized.OrderedDictionary]::new()
    # 'ResourceGroup' or 'Subscription' as emitted, or $null when not set.
    [string] $Scope
    # A literal, Param or Arm, or $null when not set.
    [BylawValue] $DeploymentLocation

    BylawDeployment() {}
}

class BylawDeployIfNotExists : BylawIfNotExists {
    # DeployIfNotExists -Type ... -Role ... { Require ...; Deployment ... } (ADR-0030, ADR-0031).
    # Value is the literal 'DeployIfNotExists', or the -Effect parameter or expression.
    # -Role values as written (ADR-0022).
    [string[]] $Roles = @()
    # Full role definition IDs, in the order written, set by the validation pass.
    [string[]] $RoleDefinitionIds = @()
    [BylawDeployment] $Deployment

    BylawDeployIfNotExists() {}

    BylawDeployIfNotExists([BylawValue] $value) : base($value) {}
}

class BylawDenyAction : BylawEffect {
    # DenyAction Delete [-CascadeBehavior Deny|Allow] (ADR-0028). Value is the literal 'DenyAction',
    # or the -Effect parameter or expression.
    # Action names as emitted: 'delete'.
    [string[]] $ActionNames = @()
    # 'deny' or 'allow' as emitted, or $null when not set.
    [string] $CascadeBehavior

    BylawDenyAction() {}

    BylawDenyAction([BylawValue] $value) : base($value) {}
}

class BylawManual : BylawEffect {
    # Manual [-DefaultState Unknown|Compliant|NonCompliant] (ADR-0028). Value is the literal
    # 'Manual', or the -Effect parameter or expression.
    # 'Unknown', 'Compliant' or 'Non-compliant' as emitted, or $null when not set.
    [string] $DefaultState

    BylawManual() {}

    BylawManual([BylawValue] $value) : base($value) {}
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
    # One Must statement, before inversion. It tests either a field (Field) or, as a value
    # condition, an expression (Subject: ResourceGroupTag, Param or Arm; ADR-0025). Exactly one of
    # the two is set.
    [BylawFieldRef] $Field
    [BylawValue] $Subject
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
        $parts.Add($(if ($null -ne $this.Field) { [string] $this.Field } else { [string] $this.Subject }))
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

class BylawConditionGroup : BylawNode {
    # AnyOf { } or AllOf { } (ADR-0026), describing the compliant state like everything else in the
    # DSL layer: AnyOf holds when any child holds. Children are BylawAssertion, BylawEach and nested
    # BylawConditionGroup nodes, in source order.
    [BylawGroupKind] $Kind
    [System.Collections.Generic.List[object]] $Children = [System.Collections.Generic.List[object]]::new()

    BylawConditionGroup() {}

    BylawConditionGroup([BylawGroupKind] $kind) {
        $this.Kind = $kind
    }
}

class BylawEach : BylawNode {
    # The [*] array path as written, e.g. 'networkAcls.ipRules[*]'.
    [BylawFieldRef] $Field
    # BylawAssertion, nested BylawEach and BylawConditionGroup nodes, in source order.
    [System.Collections.Generic.List[object]] $Children = [System.Collections.Generic.List[object]]::new()

    BylawEach() {}

    BylawEach([BylawFieldRef] $field) {
        $this.Field = $field
    }
}

class BylawRequirement : BylawNode {
    [string] $Description
    # BylawAssertion, BylawEach and BylawConditionGroup nodes, in source order.
    [System.Collections.Generic.List[object]] $Children = [System.Collections.Generic.List[object]]::new()

    BylawRequirement() {}

    BylawRequirement([string] $description) {
        $this.Description = $description
    }
}

class BylawApplicability : BylawNode {
    # One When block. Its assertions and groups are emitted as written, not inverted (ADR-0002).
    [System.Collections.Generic.List[object]] $Children = [System.Collections.Generic.List[object]]::new()
}

class BylawResourceScope : BylawNode {
    # Resource type as written, or '*' for no type condition.
    [string] $Type
    # Type in the alias snapshot's casing, set by the alias resolution pass.
    [string] $ResolvedType
    [System.Collections.Generic.List[object]] $When = [System.Collections.Generic.List[object]]::new()
    [System.Collections.Generic.List[object]] $Requirements = [System.Collections.Generic.List[object]]::new()

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
    [System.Collections.Generic.List[object]] $Parameters = [System.Collections.Generic.List[object]]::new()
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
    # Alias names marked Modifiable, ignoring case (ADR-0024). Empty when the data has none.
    hidden [System.Collections.Generic.HashSet[string]] $Modifiable

    BylawAliasSnapshot([string] $path, [string] $generatedAt, [System.Collections.IDictionary] $types) {
        $this.Init($path, $generatedAt, $types, $null)
    }

    BylawAliasSnapshot([string] $path, [string] $generatedAt, [System.Collections.IDictionary] $types, [string[]] $modifiable) {
        $this.Init($path, $generatedAt, $types, $modifiable)
    }

    hidden [void] Init([string] $path, [string] $generatedAt, [System.Collections.IDictionary] $types, [string[]] $modifiable) {
        $this.Modifiable = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($null -ne $modifiable) {
            $this.Modifiable.UnionWith($modifiable)
        }
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

    # Whether the snapshot marks the alias Modifiable, so Modify can change it.
    [bool] IsModifiable([string] $alias) {
        return $this.Modifiable.Contains($alias)
    }
}

#endregion

#region Front-end state

class BylawFrame {
    # One open keyword block (Policy, Resource, When, Require, Each, AnyOf, AllOf, Modify) while
    # the DSL runs.
    [string] $Keyword
    [BylawNode] $Node
    # Field references produced in this block that no Must has consumed yet.
    [System.Collections.Generic.List[object]] $PendingFields = [System.Collections.Generic.List[object]]::new()
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
    [object[]] $Diagnostics

    BylawCompileException([object[]] $diagnostics) : base([BylawCompileException]::FormatMessage($diagnostics)) {
        $this.Diagnostics = $diagnostics
    }

    hidden static [string] FormatMessage([object[]] $diagnostics) {
        $lines = foreach ($diagnostic in $diagnostics) {
            $diagnostic.ToString()
        }
        # LF on every OS, so messages are identical in CI logs and tests.
        return ($lines -join "`n")
    }
}

#endregion
