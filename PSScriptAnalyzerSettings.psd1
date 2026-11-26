# PSScriptAnalyzer settings for the whole repository.
#
# Suppression policy: no rule is excluded globally. Where a rule must be suppressed (for example
# PSUseApprovedVerbs / PSUseSingularNouns for DSL keywords such as Field or Properties, which by
# design do not follow Verb-Noun), use a [Diagnostics.CodeAnalysis.SuppressMessageAttribute] on
# the specific function with a Justification. Every suppression is reviewed in pull requests.
#
# Backtick line continuation is banned project-wide; PSScriptAnalyzer has no rule for it, so it is
# enforced by tests/Meta/Repository.Tests.ps1.
@{
    Severity     = @('Error', 'Warning', 'Information')
    ExcludeRules = @()
    Rules        = @{
        PSPlaceOpenBrace           = @{
            Enable             = $true
            OnSameLine         = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
        }
        PSPlaceCloseBrace          = @{
            Enable             = $true
            NewLineAfter       = $true
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore  = $false
        }
        PSUseConsistentIndentation = @{
            Enable              = $true
            IndentationSize     = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind                = 'space'
        }
        PSUseConsistentWhitespace  = @{
            Enable                          = $true
            CheckInnerBrace                 = $true
            CheckOpenBrace                  = $true
            CheckOpenParen                  = $true
            CheckOperator                   = $true
            CheckPipe                       = $true
            CheckPipeForRedundantWhitespace = $true
            CheckSeparator                  = $true
            CheckParameter                  = $false
            IgnoreAssignmentOperatorInsideHashTable = $true
        }
        PSAvoidUsingCmdletAliases  = @{
            Enable = $true
        }
        PSUseCompatibleSyntax      = @{
            Enable         = $true
            TargetVersions = @('7.0')
        }
    }
}
