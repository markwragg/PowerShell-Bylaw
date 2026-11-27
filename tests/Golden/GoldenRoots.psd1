# Golden folders, relative to the repository root, and the format each is built in (ADR-0009).
# DefinitionScope, when set, is passed to Build-Bylaw for plain JSON initiatives (ADR-0035).
# Read by tests/Golden/Golden.Tests.ps1 and by ./build/build.ps1 -Task UpdateGolden.
@{
    Roots = @(
        @{ Path = 'examples'; Format = 'Epac' }
        @{ Path = 'tests/Golden'; Format = 'Epac' }
        @{ Path = 'tests/GoldenPlainJson'; Format = 'PlainJson'; DefinitionScope = '/providers/Microsoft.Management/managementGroups/golden' }
    )
}
