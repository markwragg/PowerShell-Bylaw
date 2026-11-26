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

function DeployIfNotExists {
    <#
    .SYNOPSIS
        The deployIfNotExists effect: deploys a template when a resource has no related resource
        in the compliant state. Use it instead of Effect.

    .EXAMPLE
        DeployIfNotExists -Type 'Microsoft.Compute/virtualMachines/extensions' -Role 'Virtual Machine Contributor' {
            Require 'The antimalware extension is installed' {
                Field publisher | Must -Be 'Microsoft.Azure.Security'
            }
            Deployment -TemplateFile ./templates/antimalware.json -Parameters @{
                vmName = Arm "[field('name')]"
            }
        }
    #>
    [CmdletBinding()]
    param(
        # Require blocks that describe the related resource's compliant state, and the Deployment.
        [Parameter(Position = 0)]
        [scriptblock] $Body,

        # The related resource type, e.g. 'Microsoft.Compute/virtualMachines/extensions'.
        [string] $Type,

        # Roles the assignment's managed identity needs to deploy the template: built-in role
        # names, GUIDs or full role definition IDs (ADR-0022).
        [AllowEmptyCollection()] [AllowEmptyString()]
        [string[]] $Role,

        # The related resource's name: a literal, Param or Arm.
        [object] $Name,

        # The related resource's resource group: a literal, Param or Arm.
        [object] $ResourceGroupName,

        # Where to look for related resources: ResourceGroup (Azure's default) or Subscription.
        [string] $ExistenceScope,

        # When to evaluate after a change: AfterProvisioning, AfterProvisioningSuccess,
        # AfterProvisioningFailure, or an ISO 8601 duration up to 360 minutes, e.g. PT30M.
        [string] $EvaluationDelay,

        # The effect as a parameter, (Param Effect). Without it, the effect is DeployIfNotExists.
        [object] $Effect
    )

    $location = [BylawSourceLocation]::FromInvocation($MyInvocation, 'DeployIfNotExists')
    $frame = Test-BylawParent -Keyword 'DeployIfNotExists' -Allowed 'Policy' -Location $location
    if ($null -eq $frame -or -not (Test-BylawEffectKeyword -Frame $frame -Keyword 'DeployIfNotExists' -Location $location)) {
        return
    }

    $effectValue = Get-BylawKeywordEffectValue -Keyword 'DeployIfNotExists' -Bound $PSBoundParameters -Location $location
    $node = [BylawDeployIfNotExists]::new($effectValue)
    $node.Location = $location
    $valid = ($null -ne $effectValue) -and (Set-BylawIfNotExistsDetail -Keyword 'DeployIfNotExists' -Node $node -Bound $PSBoundParameters -Location $location)

    $roles = @($Role | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($roles.Count -eq 0) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1032' -Location $location -Message (
            "DeployIfNotExists needs -Role: the role the assignment's managed identity needs to deploy the template, e.g. DeployIfNotExists -Role 'Contributor' ... (ADR-0022)."
        )
        $valid = $false
    }
    $node.Roles = [string[]] $roles

    if ($null -eq $Body) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1043' -Location $location -Message (
            "DeployIfNotExists needs a block with a Deployment, e.g. DeployIfNotExists -Type '...' -Role 'Contributor' { Deployment -TemplateFile ./template.json }."
        )
        return
    }
    $diagnosticsBefore = $script:BylawDiagnostics.Count
    $null = Invoke-BylawIfNotExistsBody -Keyword 'DeployIfNotExists' -Node $node -Body $Body
    $innerErrors = @($script:BylawDiagnostics | Select-Object -Skip $diagnosticsBefore | Where-Object Severity -EQ ([BylawSeverity]::Error)).Count
    if ($null -eq $node.Deployment) {
        if ($innerErrors -eq 0) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1043' -Location $location -Message (
                "DeployIfNotExists needs a Deployment in its block: the template to deploy, e.g. Deployment -TemplateFile ./template.json -Parameters @{ ... }."
            )
        }
        $valid = $false
    }
    if ($valid) {
        $frame.Node.Effect = $node
    }
}

function Deployment {
    <#
    .SYNOPSIS
        The template DeployIfNotExists deploys, and the values it passes to the template's
        parameters. Use inside DeployIfNotExists.

    .EXAMPLE
        Deployment -TemplateFile ./templates/sql-tde.json -Parameters @{
            fullDbName = Arm "[field('fullName')]"
        }
    #>
    [CmdletBinding()]
    param(
        # An ARM template JSON file, relative to the .bylaw.ps1 file's folder.
        [string] $TemplateFile,

        # The ARM template as a hashtable. Use [ordered] to keep its key order.
        [System.Collections.IDictionary] $Template,

        # Template parameter name -> value: a literal, Param, Arm or ResourceGroupTag.
        [System.Collections.IDictionary] $Parameters,

        # Where to deploy: ResourceGroup (Azure's default) or Subscription.
        [string] $Scope,

        # The deployment's location: a literal, Param or Arm. Required with -Scope Subscription.
        [object] $Location
    )

    $sourceLocation = [BylawSourceLocation]::FromInvocation($MyInvocation, 'Deployment')
    $frame = Test-BylawParent -Keyword 'Deployment' -Allowed 'DeployIfNotExists' -Location $sourceLocation
    if ($null -eq $frame -or -not (Test-BylawSingleton -Frame $frame -Keyword 'Deployment' -Location $sourceLocation)) {
        return
    }

    $node = [BylawDeployment]::new()
    $node.Location = $sourceLocation
    $valid = $true

    $hasFile = $PSBoundParameters.ContainsKey('TemplateFile')
    $hasTemplate = $PSBoundParameters.ContainsKey('Template')
    if ($hasFile -eq $hasTemplate) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1044' -Location $sourceLocation -Message (
            'Deployment takes exactly one of -TemplateFile (an ARM template JSON file) and -Template (a hashtable).'
        )
        return
    }
    $template = if ($hasFile) {
        Read-BylawTemplateFile -Path $TemplateFile -Location $sourceLocation
    }
    else {
        if (Test-BylawNestedValue -Value $Template) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1045' -Location $sourceLocation -Message (
                "-Template can't contain Param or Arm: it is an ARM template, evaluated by the deployment. Pass policy values with -Parameters, and use them in the template as [parameters('name')]."
            )
            $null
        }
        else {
            $Template
        }
    }
    if ($null -eq $template) {
        return
    }
    if (-not (Test-BylawTemplateShape -Template $template -Location $sourceLocation)) {
        return
    }
    $node.Template = $template
    if ($hasFile) {
        $node.TemplateFile = Resolve-BylawTemplatePath -Path $TemplateFile -Location $sourceLocation
    }

    if ($PSBoundParameters.ContainsKey('Parameters')) {
        # An [ordered] hashtable keeps its order. A plain one is sorted, as the JSON writer does
        # (ADR-0009): its own order changes from one process to the next.
        $keys = [string[]] @($Parameters.Keys)
        if ($Parameters -isnot [System.Collections.Specialized.IOrderedDictionary]) {
            [array]::Sort($keys, [System.StringComparer]::Ordinal)
        }
        foreach ($key in $keys) {
            $value = ConvertTo-BylawValue -Value $Parameters[$key] -Location $sourceLocation
            if ($null -eq $value) {
                $valid = $false
                continue
            }
            $node.Parameters[[string] $key] = $value
        }
    }

    if ($PSBoundParameters.ContainsKey('Scope')) {
        $scopeName = $script:BylawExistenceScopes | Where-Object { $_ -eq $Scope } | Select-Object -First 1
        if ($scopeName) {
            $node.Scope = $scopeName
        }
        else {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1040' -Location $sourceLocation -Message (
                "-Scope '$Scope' is not valid. Use ResourceGroup or Subscription."
            )
            $valid = $false
        }
    }
    if ($PSBoundParameters.ContainsKey('Location')) {
        if (-not ($Location -is [string] -or $Location -is [BylawParamRef] -or $Location -is [BylawExpr]) -or ($Location -is [string] -and [string]::IsNullOrWhiteSpace($Location))) {
            Add-BylawDiagnostic -Severity Error -Code 'BYL1039' -Location $sourceLocation -Message (
                '-Location takes a location, a parameter or an Arm expression, e.g. -Location (Param Location).'
            )
            $valid = $false
        }
        else {
            $node.DeploymentLocation = ConvertTo-BylawValue -Value $Location -Location $sourceLocation
        }
    }
    if ($node.Scope -eq 'Subscription' -and -not $PSBoundParameters.ContainsKey('Location')) {
        Add-BylawDiagnostic -Severity Error -Code 'BYL1046' -Location $sourceLocation -Message (
            'A subscription-scope deployment needs -Location, e.g. -Location (Param Location). Azure requires a location for subscription deployments.'
        )
        $valid = $false
    }

    if ($valid) {
        $frame.Node.Deployment = $node
    }
}

function Resolve-BylawTemplatePath {
    # The full path of a template file, relative to the folder of the file Deployment is in.
    param([Parameter(Mandatory)] [string] $Path, [BylawSourceLocation] $Location)

    $base = if ($Location -and $Location.File) { [System.IO.Path]::GetDirectoryName($Location.File) } else { (Get-Location).ProviderPath }
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($base, $Path))
}

function Read-BylawTemplateFile {
    # The template in a JSON file, as ordered dictionaries; $null after recording BYL1045.
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Path, [BylawSourceLocation] $Location)

    $report = {
        param([string] $Message)
        Add-BylawDiagnostic -Severity Error -Code 'BYL1045' -Location $Location -Message $Message
    }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        & $report '-TemplateFile needs the path of an ARM template JSON file, relative to this file.'
        return $null
    }
    if ($Path.EndsWith('.bicep', [System.StringComparison]::OrdinalIgnoreCase)) {
        & $report "-TemplateFile '$Path' is a Bicep file. Bicep isn't supported yet: build it to JSON with 'bicep build', and use the .json file (ADR-0031)."
        return $null
    }
    $fullPath = Resolve-BylawTemplatePath -Path $Path -Location $Location
    if (-not [System.IO.File]::Exists($fullPath)) {
        & $report "Template file '$Path' was not found (looked for $fullPath). Paths are relative to the .bylaw.ps1 file's folder."
        return $null
    }
    try {
        ConvertFrom-BylawJson -Json ([System.IO.File]::ReadAllText($fullPath))
    }
    catch {
        $exception = $_.Exception
        while ($null -ne $exception.InnerException) {
            $exception = $exception.InnerException
        }
        & $report "Template file '$Path' is not valid JSON: $($exception.Message)"
        $null
    }
}

function Test-BylawTemplateShape {
    # An ARM template is an object with a resources array. Records BYL1045 and returns $false
    # otherwise.
    param([AllowNull()] [object] $Template, [BylawSourceLocation] $Location)

    $resources = if ($Template -is [System.Collections.IDictionary]) { Get-BylawTemplateKey -Object $Template -Key 'resources' } else { $null }
    if ($null -ne $resources -and ($resources.Value -is [System.Collections.IList])) {
        return $true
    }
    Add-BylawDiagnostic -Severity Error -Code 'BYL1045' -Location $Location -Message (
        'The template is not an ARM template: it needs to be an object with a resources array, e.g. @{ ''$schema'' = ''...''; contentVersion = ''1.0.0.0''; resources = @() }.'
    )
    $false
}

function Get-BylawTemplateKey {
    # The entry of a template object whose key matches, ignoring case as ARM does: @{ Key; Value },
    # or $null.
    param([Parameter(Mandatory)] [System.Collections.IDictionary] $Object, [Parameter(Mandatory)] [string] $Key)

    foreach ($candidate in $Object.Keys) {
        if ([string]::Equals([string] $candidate, $Key, [System.StringComparison]::OrdinalIgnoreCase)) {
            return @{ Key = [string] $candidate; Value = $Object[$candidate] }
        }
    }
    $null
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
