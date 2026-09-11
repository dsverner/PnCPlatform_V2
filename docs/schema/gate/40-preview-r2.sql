/* Gate step 5 (§2.6): run rule R2 in preview. Expected subjects: T1, T4. */
SET NOCOUNT ON;
EXEC compliance.RunRulePreview N'R2', '22222222-2222-2222-2222-222222222222';
