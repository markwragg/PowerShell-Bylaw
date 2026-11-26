# Every Must operator, in a Require: strict, negated, and lenient with -IfPresent (ADR-0004, ADR-0015).

Policy 'golden-operators-strict' {
    Properties @{ DisplayName = 'Golden: operators, strict'; Category = 'Golden'; Version = '1.0.0'; Mode = 'Indexed' }

    Resource 'Microsoft.KeyVault/vaults' {
        Require 'Every operator' {
            Field sku.name | Must -Be 'premium'
            Field publicNetworkAccess | Must -BeIn 'Disabled', 'SecuredByPerimeter'
            Field networkAcls.defaultAction | Must -BeLike 'D*'
            Field name | Must -Match 'kv-???-##'
            Field name | Must -MatchCase 'kv-???-##'
            Field networkAcls.bypass | Must -ContainText 'AzureServices'
            Field tags | Must -ContainKey 'owner'
            Field enableRbacAuthorization | Must -Exist
            Field softDeleteRetentionInDays | Must -BeGreaterThan 6
            Field softDeleteRetentionInDays | Must -BeGreaterOrEqual 7
            Field softDeleteRetentionInDays | Must -BeLessThan 91
            Field softDeleteRetentionInDays | Must -BeLessOrEqual 90
        }
    }

    Effect Deny
}

Policy 'golden-operators-not' {
    Properties @{ DisplayName = 'Golden: operators, negated'; Category = 'Golden'; Version = '1.0.0'; Mode = 'Indexed' }

    Resource 'Microsoft.KeyVault/vaults' {
        Require 'Every operator, negated' {
            Field sku.name | Must -Not -Be 'standard'
            Field publicNetworkAccess | Must -Not -BeIn 'Enabled'
            Field networkAcls.defaultAction | Must -Not -BeLike 'A*'
            Field name | Must -Not -Match 'tmp-#'
            Field name | Must -Not -MatchCase 'TMP-#'
            Field networkAcls.bypass | Must -Not -ContainText 'None'
            Field tags | Must -Not -ContainKey 'temporary'
            Field networkAcls.ipRules | Must -Not -Exist
            Field softDeleteRetentionInDays | Must -Not -BeGreaterThan 90
            Field softDeleteRetentionInDays | Must -Not -BeGreaterOrEqual 91
            Field softDeleteRetentionInDays | Must -Not -BeLessThan 7
            Field softDeleteRetentionInDays | Must -Not -BeLessOrEqual 6
        }
    }

    Effect Deny
}

Policy 'golden-operators-if-present' {
    Properties @{ DisplayName = 'Golden: operators, lenient'; Category = 'Golden'; Version = '1.0.0'; Mode = 'Indexed' }

    Resource 'Microsoft.KeyVault/vaults' {
        Require 'Every operator, if present' {
            Field sku.name | Must -Be 'premium' -IfPresent
            Field publicNetworkAccess | Must -BeIn 'Disabled', 'SecuredByPerimeter' -IfPresent
            Field networkAcls.defaultAction | Must -BeLike 'D*' -IfPresent
            Field name | Must -Match 'kv-???-##' -IfPresent
            Field name | Must -MatchCase 'kv-???-##' -IfPresent
            Field networkAcls.bypass | Must -ContainText 'AzureServices' -IfPresent
            Field tags | Must -ContainKey 'owner' -IfPresent
            Field softDeleteRetentionInDays | Must -BeGreaterThan 6 -IfPresent
            Field softDeleteRetentionInDays | Must -BeGreaterOrEqual 7 -IfPresent
            Field softDeleteRetentionInDays | Must -BeLessThan 91 -IfPresent
            Field softDeleteRetentionInDays | Must -BeLessOrEqual 90 -IfPresent
        }

        Require 'Every negated operator, if present' {
            Field sku.name | Must -Not -Be 'standard' -IfPresent
            Field publicNetworkAccess | Must -Not -BeIn 'Enabled' -IfPresent
            Field networkAcls.defaultAction | Must -Not -BeLike 'A*' -IfPresent
            Field name | Must -Not -Match 'tmp-#' -IfPresent
            Field name | Must -Not -MatchCase 'TMP-#' -IfPresent
            Field networkAcls.bypass | Must -Not -ContainText 'None' -IfPresent
            Field tags | Must -Not -ContainKey 'temporary' -IfPresent
            Field softDeleteRetentionInDays | Must -Not -BeGreaterThan 90 -IfPresent
            Field softDeleteRetentionInDays | Must -Not -BeGreaterOrEqual 91 -IfPresent
            Field softDeleteRetentionInDays | Must -Not -BeLessThan 7 -IfPresent
            Field softDeleteRetentionInDays | Must -Not -BeLessOrEqual 6 -IfPresent
        }
    }

    Effect Audit
}
