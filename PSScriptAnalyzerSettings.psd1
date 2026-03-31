@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'                        # Intentional: console UI
        'PSUseShouldProcessForStateChangingFunctions'
        'PSAvoidGlobalVars'                            # Architectural: cross-module logging
        'PSUseDeclaredVarsMoreThanAssignments'         # False positives on module-scoped vars
        'PSAvoidUsingEmptyCatchBlock'                  # Intentional in Phase1
        'PSPossibleIncorrectComparisonWithNull'        # Legacy style, tracked in TODO.md
        'PSAvoidOverwritingBuiltInCmdlets'             # Write-Log is our custom function
        'PSAvoidUsingInvokeExpression'                 # Known issue, tracked in TODO.md §1.5
    )
    Rules        = @{
        PSUseCompatibleSyntax = @{
            Enable         = $true
            TargetVersions = @('5.1', '7.6')   # 5.1 is the binding constraint
        }
    }
}
