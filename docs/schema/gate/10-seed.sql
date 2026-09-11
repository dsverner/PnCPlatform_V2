/* ============================================================================
   Gate step 2 (§2.6): seed reference rows, a template with ONE catalogue characteristic,
   a formula deriving a second fact, and an obligation rule referencing both.
   TOY DATA. Asset names and values are invented for the gate and assert nothing about
   any real installation.
   ============================================================================ */
SET NOCOUNT ON;

INSERT ref.DefinitionKind (DefinitionKind, MetaKind) VALUES
    (N'CharacteristicSchema.AssetTemplate', N'CharacteristicSchema'),
    (N'Program.Formula',                    N'Program'),
    (N'Program.ObligationRule',             N'Program');
INSERT ref.Unit (UnitCode, Name) VALUES (N'kV', N'kilovolt'), (N'A', N'ampere');
INSERT ref.AssetType (AssetTypeCode, Name) VALUES (N'Relay', N'Protective relay (toy)');

/* two actors so the segregation check on approval has something to enforce */
INSERT personnel.Actor (ActorId, DisplayName) VALUES
    ('11111111-1111-1111-1111-111111111111', N'Toy Author'),
    ('22222222-2222-2222-2222-222222222222', N'Toy Approver');
GO

DECLARE @author   UNIQUEIDENTIFIER = '11111111-1111-1111-1111-111111111111';
DECLARE @approver UNIQUEIDENTIFIER = '22222222-2222-2222-2222-222222222222';

/* --- template v1: one characteristic, flagged as a catalogue fact ------------------- */
EXEC config.AddDefinition N'CharacteristicSchema.AssetTemplate', N'ToyRelayTemplate', N'Toy relay template', NULL, @author;
EXEC config.AddDefinitionVersion N'ToyRelayTemplate', N'v1: technology only', NULL, @author;
EXEC config.AddCharacteristic N'ToyRelayTemplate', 1, N'technology', N'Relay technology', N'Enumeration',
     NULL, NULL, 1, N'["Microprocessor","Electromechanical","Static"]', 1, 1, @author;
EXEC config.ApproveDefinitionVersion N'ToyRelayTemplate', 1, @approver;

/* --- six toy assets ----------------------------------------------------------------- */
EXEC asset.AddAsset N'T1', N'Relay', N'ToyRelayTemplate', @author;
EXEC asset.AddAsset N'T2', N'Relay', N'ToyRelayTemplate', @author;
EXEC asset.AddAsset N'T3', N'Relay', N'ToyRelayTemplate', @author;
EXEC asset.AddAsset N'T4', N'Relay', N'ToyRelayTemplate', @author;
EXEC asset.AddAsset N'T5', N'Relay', N'ToyRelayTemplate', @author;
EXEC asset.AddAsset N'T6', N'Relay', N'ToyRelayTemplate', @author;

EXEC asset.SetCharacteristicValue N'T1', N'technology', @textValue = N'Microprocessor',    @actorId = @author;
EXEC asset.SetCharacteristicValue N'T2', N'technology', @textValue = N'Microprocessor',    @actorId = @author;
EXEC asset.SetCharacteristicValue N'T3', N'technology', @textValue = N'Electromechanical', @actorId = @author;
EXEC asset.SetCharacteristicValue N'T4', N'technology', @textValue = N'Microprocessor',    @actorId = @author;
EXEC asset.SetCharacteristicValue N'T5', N'technology', @textValue = N'Static',            @actorId = @author;
EXEC asset.SetCharacteristicValue N'T6', N'technology', @textValue = N'Microprocessor',    @actorId = @author;

/* --- formula: a second fact derived from the first ---------------------------------- */
EXEC config.AddDefinition N'Program.Formula', N'is_microprocessor', N'Is a microprocessor relay', NULL, @author;
EXEC config.AddDefinitionVersion N'is_microprocessor', N'v1', N'{"fact":"asset.template.technology","op":"=","value":"Microprocessor"}', @author;
EXEC config.ApproveDefinitionVersion N'is_microprocessor', 1, @approver;

/* --- rule R1: predicate over the derived fact --------------------------------------- */
EXEC config.AddDefinition N'Program.ObligationRule', N'R1', N'Toy rule 1: microprocessor relays', NULL, @author;
EXEC config.AddDefinitionVersion N'R1', N'v1',
     N'{"requirement":"toy","subjectKinds":["Asset"],"predicate":{"fact":"asset.formula.is_microprocessor","op":"=","value":true}}', @author;
EXEC config.ApproveDefinitionVersion N'R1', 1, @approver;
GO
