# AuditIfNotExists (ADR-0030). It takes the place of Effect; its parameters say which related
# resources to check, and its Require blocks describe the related resource's compliant state.

$script:BylawExistenceScopes = @('ResourceGroup', 'Subscription')
$script:BylawEvaluationDelays = @('AfterProvisioning', 'AfterProvisioningSuccess', 'AfterProvisioningFailure')

function AuditIfNotExists {
    <#
    .SYNOPSIS
        The auditIfNotExists effect: audits a resource that has no related resource in the
        compliant state. Use it instead of Effect.

    .EXAMPLE
        AuditIfNotExists -Type 'Microsoft.Compute/virtualMachines/extensions' {
            Require 'The antimalware extension is installed' {
                Field publisher | Must -Be 'Microsoft.Azure.Security'
                Field type | Must -Be 'IaaSAntimalware'
            }
        }
    #>
    [CmdletBinding()]
    param(
        # Require blocks that describe the related resource's compliant state.
        [Parameter(Position = 0)]
        [scriptblock] $Body,

        # The related resource type, e.g. 'Microsoft.Compute/virtualMachines/extensions'.
        [string] $Type,

        # The related resource's name: a literal, Param or Arm.
        [object] $Name,

        # The related resource's resource group: a literal, Param or Arm.
        [object] $ResourceGroupName,

        # Where to look for related resources: ResourceGroup (Azure's default) or Subscription.
        [string] $ExistenceScope,

        # When to evaluate after a change: AfterProvisioning, AfterProvisioningSuccess,
        # AfterProvisioningFailure, or an ISO 8601 duration up to 360 minutes, e.g. PT30M.
        [string] $EvaluationDelay,

        # The effect as a parameter, (Param Effect). Without it, the effect is AuditIfNotExists.
        [object] $Effect
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'AuditIfNotExists')
    $frame = Test-BylawParent -Keyword 'AuditIfNotExists' -Allowed 'Policy' -Location $location
    if ($null -eq $frame -or -not (Test-BylawEffectKeyword -Frame $frame -Keyword 'AuditIfNotExists' -Location $location)) {
        return
    }

    $effectValue = Get-BylawKeywordEffectValue -Keyword 'AuditIfNotExists' -Bound $PSBoundParameters -Location $location
    $node = [BylawAuditIfNotExists]::new($effectValue)
    $node.Location = $location
    $valid = ($null -ne $effectValue) -and (Set-BylawIfNotExistsDetail -Keyword 'AuditIfNotExists' -Node $node -Bound $PSBoundParameters -Location $location)
    if (Invoke-BylawIfNotExistsBody -Keyword 'AuditIfNotExists' -Node $node -Body $Body) {
        if ($valid) {
            $frame.Node.Effect = $node
        }
    }
}

function Set-BylawIfNotExistsDetail {
    # Checks and sets the related-resource parameters shared by AuditIfNotExists and
    # DeployIfNotExists. Returns $false after recording diagnostics when any is invalid.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Sets properties of an in-memory IR node only.')]
    param(
        [Parameter(Mandatory)] [string] $Keyword,
        [Parameter(Mandatory)] [BylawIfNotExists] $Node,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Bound,
        [BylawSourceLocation] $Location
    )

    $valid = $true
    $type = [string] $Bound['Type']
    if ([string]::IsNullOrWhiteSpace($type) -or -not $type.Contains('/')) {
        $written = if ([string]::IsNullOrWhiteSpace($type)) { "$Keyword needs -Type" } else { "-Type '$type' is not a resource type" }
        Add-BylawDiagnostic -Severity Error -Code 'BYL1038' -Location $Location -Message (
            "$written`: the type of the related resource to check, e.g. $Keyword -Type 'Microsoft.Compute/virtualMachines/extensions' { ... }."
        )
        $valid = $false
    }
    $Node.Type = $type

    foreach ($parameterName in 'Name', 'ResourceGroupName') {
        if (-not $Bound.ContainsKey($parameterName)) {
            continue
        }
        $raw = $Bound[$parameterName]
        if (-not ($raw -is [string] -or $raw -is [BylawParamRef] -or $raw -is [BylawExpr]) -or ($raw -is [string] -and [string]::IsNullOrWhiteSpace($raw))) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1039' -Location $Location -Message (
                "-$parameterName takes a name, a parameter or an Arm expression, e.g. -$parameterName (Arm `"[field('name')]`")."
            )
            $valid = $false
            continue
        }
        $Node.$parameterName = ConvertTo-BylawValue -Value $raw -Location $Location
    }

    if ($Bound.ContainsKey('ExistenceScope')) {
        $scope = $script:BylawExistenceScopes | Where-Object { $_ -eq $Bound['ExistenceScope'] } | Select-Object -First 1
        if ($scope) {
            $Node.ExistenceScope = $scope
        }
        else {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1040' -Location $Location -Message (
                "-ExistenceScope '$($Bound['ExistenceScope'])' is not valid. Use ResourceGroup or Subscription."
            )
            $valid = $false
        }
    }

    if ($Bound.ContainsKey('EvaluationDelay')) {
        $delay = Get-BylawEvaluationDelay -Value ([string] $Bound['EvaluationDelay'])
        if ($delay) {
            $Node.EvaluationDelay = $delay
        }
        else {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1041' -Location $Location -Message (
                "-EvaluationDelay '$($Bound['EvaluationDelay'])' is not valid. Use AfterProvisioning, AfterProvisioningSuccess, AfterProvisioningFailure, or an ISO 8601 duration from 0 to 360 minutes, e.g. PT30M."
            )
            $valid = $false
        }
    }
    $valid
}

function Get-BylawEvaluationDelay {
    # The evaluation delay as emitted, or $null when it isn't valid: a keyword in canonical casing,
    # or an ISO 8601 duration of 0 to 360 minutes in upper case.
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Value)

    $keyword = $script:BylawEvaluationDelays | Where-Object { $_ -eq $Value } | Select-Object -First 1
    if ($keyword) {
        return $keyword
    }
    $duration = $Value.ToUpperInvariant()
    if ($duration -notmatch '^P(T(\d+H)?(\d+M)?(\d+S)?|\d+D)$' -or $duration -eq 'PT') {
        return $null
    }
    try {
        $span = [System.Xml.XmlConvert]::ToTimeSpan($duration)
    }
    catch {
        return $null
    }
    if ($span -lt [timespan]::Zero -or $span -gt [timespan]::FromMinutes(360)) {
        return $null
    }
    $duration
}

function Invoke-BylawIfNotExistsBody {
    # Runs the Require blocks that describe the related resource. Returns $false when the body
    # had errors that leave the effect unusable.
    param(
        [Parameter(Mandatory)] [string] $Keyword,
        [Parameter(Mandatory)] [BylawIfNotExists] $Node,
        [AllowNull()] [scriptblock] $Body
    )

    if ($null -eq $Body) {
        # No existence condition: any related resource of the type satisfies the effect.
        return $true
    }
    $bodyFrame = Enter-BylawFrame -Keyword $Keyword -Node $Node
    try {
        Invoke-BylawBlock -Body $Body
    }
    finally {
        Exit-BylawFrame -Frame $bodyFrame
    }
    $true
}
