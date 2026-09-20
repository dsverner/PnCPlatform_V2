-- #204 (2026-09-19): the instrument transformer tests as procedures — CT_TEST (ratio, polarity, excitation curve, engineer's
-- review) and VT_TEST (ratio, polarity, review). The owner (#201): "Instrument transformers should be first class devices in
-- their own right with testing (saturation curves, ratio and polarity etc.)". A test plan in V2 is a Program.Procedure document
-- (config.TestPlanStep was removed in W0, STEPS.md): each step's captures are the readings, each commit produces the
-- record.Record the step names (TestSheet; the engineer's review an Attestation), against the transformer the request is
-- scoped to. No formula expression in these documents, so no compiler is needed to seed them; no reading limit is
-- enforced here (a CT's ratio-error acceptance depends on its class — a rule to come as data): the technician's outcome and
-- the engineer's review are the verdict, as the requirements' split says (the test tool keeps its raw artefact; the platform
-- owns the accepted result and the readings). Loaded through process.AddProcedureVersion and approved by the seed approver
-- ONLY while no Effective version exists — a deploy never overturns what a person authored (the DRAWING_REVISION rule, #121).
IF OBJECT_ID(N'[process].[AddProcedureVersion]') IS NULL RETURN;   -- bootstrap (tables-only) publish
GO
-- ---------------------------------------------------------------- CT_TEST
IF EXISTS (SELECT 1 FROM [config].[Definition] d JOIN [config].[DefinitionVersion] v ON v.[DefinitionEntityId] = d.[EntityId] AND v.[IsDeleted] = 0
           WHERE d.[DefinitionKind] = N'Program.Procedure' AND d.[DefinitionKey] = N'CT_TEST' AND d.[IsDeleted] = 0 AND v.[Status] = N'Effective') RETURN;
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
DECLARE @doc NVARCHAR(MAX) = N'{"g":1,"kind":"procedure","key":"CT_TEST","name":"Current transformer test","description":"Ratio, polarity and excitation (saturation) curve of a current transformer, each a test sheet against the transformer, reviewed by an engineer (#204).","subjectKind":"Asset","roles":{"technician":{"role":"PCTechnician"},"engineer":{"role":"PCEngineer"}},"outcomes":["Completed","Cancelled"],"body":{"block":"sequence","id":"MAIN","items":[
{"block":"step","id":"RATIO","title":"[1] Ratio test","instruction":"Inject on the tap in service (the nameplate says which) and read the secondary. Record the tap, the applied and measured currents, the ratio found and its error against the nameplate ratio. Attach the test set report if there is one.","role":"technician","capture":{"tap":{"type":"text","required":true},"appliedPrimaryA":{"type":"num","unit":"A"},"measuredSecondaryA":{"type":"num","unit":"A"},"ratioMeasured":{"type":"num","required":true},"ratioErrorPercent":{"type":"num","unit":"%"},"method":{"type":"text","allowed":["Primary injection","Secondary injection","Test set"]}},"evidence":{"required":false,"kinds":["TestSheet"]},"outcomes":["Pass","Fail"],"record":{"kind":"TestSheet"}},
{"block":"step","id":"POLARITY","title":"[2] Polarity test","instruction":"Confirm the marked polarity terminals against the wiring: a DC kick, a primary injection with the relay reading, or the test set. Record the result and the method.","role":"technician","capture":{"polarity":{"type":"text","allowed":["Correct","Reversed"],"required":true},"method":{"type":"text","allowed":["DC kick","Primary injection","Test set"]}},"outcomes":["Pass","Fail"],"record":{"kind":"TestSheet"}},
{"block":"step","id":"EXCITATION","title":"[3] Excitation (saturation) curve","instruction":"Energise the secondary with the primary open and take the voltage-current points up through the knee. Record the knee point (voltage and current) and the points as read, one V, I pair per line; attach the test set export.","role":"technician","capture":{"kneePointVoltageV":{"type":"num","unit":"V","required":true},"kneePointCurrentA":{"type":"num","unit":"A"},"points":{"type":"text"},"method":{"type":"text","allowed":["Test set","Manual"]}},"evidence":{"required":false,"kinds":["TestSheet"]},"outcomes":["Pass","Fail","Marginal"],"record":{"kind":"TestSheet"}},
{"block":"step","id":"REVIEW","title":"[4] Engineer review","instruction":"Review the three sheets against the nameplate (ratio in use, accuracy class, knee point) and accept or reject the test. Say why either way.","role":"engineer","capture":{"remarks":{"type":"text"}},"outcomes":["Accepted","Rejected"],"record":{"kind":"Attestation"}}
]}}';
DECLARE @def UNIQUEIDENTIFIER, @ver UNIQUEIDENTIFIER, @no INT, @existing BIT;
EXEC [process].[AddProcedureVersion] @Canonical = @doc, @ChangeNote = N'seed (#204): CT ratio, polarity, excitation, review', @ActorId = @author,
     @DefinitionEntityId = @def OUTPUT, @VersionRowId = @ver OUTPUT, @VersionNumber = @no OUTPUT, @Existing = @existing OUTPUT;
IF EXISTS (SELECT 1 FROM [config].[DefinitionVersion] WHERE [RowId] = @ver AND [Status] = N'Draft')
    EXEC [process].[ApproveProcedureVersion] @VersionRowId = @ver, @ActorId = @approver;
GO
-- ---------------------------------------------------------------- VT_TEST
IF EXISTS (SELECT 1 FROM [config].[Definition] d JOIN [config].[DefinitionVersion] v ON v.[DefinitionEntityId] = d.[EntityId] AND v.[IsDeleted] = 0
           WHERE d.[DefinitionKind] = N'Program.Procedure' AND d.[DefinitionKey] = N'VT_TEST' AND d.[IsDeleted] = 0 AND v.[Status] = N'Effective') RETURN;
DECLARE @author   UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001';
DECLARE @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';
DECLARE @doc NVARCHAR(MAX) = N'{"g":1,"kind":"procedure","key":"VT_TEST","name":"Voltage transformer test","description":"Ratio and polarity of a voltage transformer (inductive, CVT or CCPD), each a test sheet against the transformer, reviewed by an engineer (#204).","subjectKind":"Asset","roles":{"technician":{"role":"PCTechnician"},"engineer":{"role":"PCEngineer"}},"outcomes":["Completed","Cancelled"],"body":{"block":"sequence","id":"MAIN","items":[
{"block":"step","id":"RATIO","title":"[1] Ratio test","instruction":"Energise the primary (or inject on the secondary) on the winding in service and read the other side. Record the winding, the applied and measured voltages, the ratio found and its error against the nameplate ratio.","role":"technician","capture":{"winding":{"type":"text","required":true},"appliedPrimaryV":{"type":"num","unit":"V"},"measuredSecondaryV":{"type":"num","unit":"V"},"ratioMeasured":{"type":"num","required":true},"ratioErrorPercent":{"type":"num","unit":"%"},"method":{"type":"text","allowed":["Primary energisation","Secondary injection","Test set"]}},"evidence":{"required":false,"kinds":["TestSheet"]},"outcomes":["Pass","Fail"],"record":{"kind":"TestSheet"}},
{"block":"step","id":"POLARITY","title":"[2] Polarity test","instruction":"Confirm the marked polarity terminals against the wiring. Record the result and the method.","role":"technician","capture":{"polarity":{"type":"text","allowed":["Correct","Reversed"],"required":true},"method":{"type":"text","allowed":["DC kick","Primary energisation","Test set"]}},"outcomes":["Pass","Fail"],"record":{"kind":"TestSheet"}},
{"block":"step","id":"REVIEW","title":"[3] Engineer review","instruction":"Review the sheets against the nameplate (ratio in use, accuracy class) and accept or reject the test. Say why either way.","role":"engineer","capture":{"remarks":{"type":"text"}},"outcomes":["Accepted","Rejected"],"record":{"kind":"Attestation"}}
]}}';
DECLARE @def UNIQUEIDENTIFIER, @ver UNIQUEIDENTIFIER, @no INT, @existing BIT;
EXEC [process].[AddProcedureVersion] @Canonical = @doc, @ChangeNote = N'seed (#204): VT ratio, polarity, review', @ActorId = @author,
     @DefinitionEntityId = @def OUTPUT, @VersionRowId = @ver OUTPUT, @VersionNumber = @no OUTPUT, @Existing = @existing OUTPUT;
IF EXISTS (SELECT 1 FROM [config].[DefinitionVersion] WHERE [RowId] = @ver AND [Status] = N'Draft')
    EXEC [process].[ApproveProcedureVersion] @VersionRowId = @ver, @ActorId = @approver;
GO
