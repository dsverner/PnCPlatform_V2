/* Gate step 3 (§2.6): run rule R1 in preview. Expected subjects: T1, T2, T4, T6. */
SET NOCOUNT ON;
EXEC compliance.RunRulePreview N'R1', '22222222-2222-2222-2222-222222222222';
