/* ============================================================================
   Gate step 4 (§2.6): ROWS ONLY.
   A new template version adds a second characteristic, flagged as a catalogue fact;
   values are entered; a second rule references the new fact.
   This file must contain no CREATE, ALTER or DROP. run_gate.py checks that, and hashes
   every object definition before this file and after 40-preview-r2.sql.
   TOY DATA: the kV figures are invented for the gate.
   ============================================================================ */
SET NOCOUNT ON;
DECLARE @author   UNIQUEIDENTIFIER = '11111111-1111-1111-1111-111111111111';
DECLARE @approver UNIQUEIDENTIFIER = '22222222-2222-2222-2222-222222222222';

/* --- template v2: the v1 characteristic plus a new one --------------------------- */
EXEC config.AddDefinitionVersion N'ToyRelayTemplate', N'v2: add voltage_class_kv', NULL, @author;
EXEC config.AddCharacteristic N'ToyRelayTemplate', 2, N'technology', N'Relay technology', N'Enumeration',
     NULL, NULL, 1, N'["Microprocessor","Electromechanical","Static"]', 1, 1, @author;
EXEC config.AddCharacteristic N'ToyRelayTemplate', 2, N'voltage_class_kv', N'Voltage class', N'Decimal',
     N'kV', N'Primary', 0, NULL, 1, 2, @author;
EXEC config.ApproveDefinitionVersion N'ToyRelayTemplate', 2, @approver;

/* --- values for the new characteristic ------------------------------------------- */
EXEC asset.SetCharacteristicValue N'T1', N'voltage_class_kv', @decimalValue = 138, @actorId = @author;
EXEC asset.SetCharacteristicValue N'T2', N'voltage_class_kv', @decimalValue = 69,  @actorId = @author;
EXEC asset.SetCharacteristicValue N'T3', N'voltage_class_kv', @decimalValue = 138, @actorId = @author;
EXEC asset.SetCharacteristicValue N'T4', N'voltage_class_kv', @decimalValue = 230, @actorId = @author;
EXEC asset.SetCharacteristicValue N'T5', N'voltage_class_kv', @decimalValue = 345, @actorId = @author;
EXEC asset.SetCharacteristicValue N'T6', N'voltage_class_kv', @decimalValue = 69,  @actorId = @author;

/* --- rule R2: references the v1 fact and the new fact ---------------------------- */
EXEC config.AddDefinition N'Program.ObligationRule', N'R2', N'Toy rule 2: microprocessor relays at 100 kV and above', NULL, @author;
EXEC config.AddDefinitionVersion N'R2', N'v1',
     N'{"requirement":"toy","subjectKinds":["Asset"],"predicate":{"all":[
          {"fact":"asset.template.technology","op":"=","value":"Microprocessor"},
          {"fact":"asset.template.voltage_class_kv","op":">=","value":100}]}}', @author;
EXEC config.ApproveDefinitionVersion N'R2', 1, @approver;
GO
