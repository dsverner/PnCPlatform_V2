-- Database roles for the privilege boundary of SCHEMA-DESIGN §0.5 and §15.3 (decision 184).
-- Membership (logins → users → roles) is environment configuration, not project content.
--   app_execute  : the application login. EXECUTE on procedures, SELECT on views. Nothing else.
--   agent_backup : the SQL Agent service account. Reads the effective backup policy, writes
--                  audit.BackupRun / audit.RestoreTest through its own procedure.
--   platform_admin: DBA/installer only; never the application.
CREATE ROLE [app_execute];
GO
CREATE ROLE [agent_backup];
GO
CREATE ROLE [platform_admin];
GO
-- Schema-level grants. Tables receive no grant: the roles reach data only through views and
-- procedures, which is what makes the write path (§0.5) and read logging (decision 65) hold.
GRANT EXECUTE ON SCHEMA::[location]   TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[asset]      TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[device]     TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[connection] TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[scheme]     TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[document]   TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[work]       TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[record]     TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[party]      TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[personnel]  TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[security]   TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[compliance] TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[network]    TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[event]      TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[config]     TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[ref]        TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[audit]      TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[migration]  TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[archive]    TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[core]       TO [app_execute];
GO
GRANT EXECUTE ON SCHEMA::[process]    TO [app_execute];
GO
-- VIEW DEFINITION on the same schemas: the application reads each procedure's parameter list and T-SQL defaults
-- (OBJECT_DEFINITION) to build its catalog; without it every parameter looks required. Found on QA 2026-09-07
-- (decision 256): DEV never showed it because dev_pnc is db_owner. Procedure text is the platform's own, not data.
GRANT VIEW DEFINITION ON SCHEMA::[location] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[asset] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[device] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[connection] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[scheme] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[document] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[work] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[record] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[party] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[personnel] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[security] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[compliance] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[network] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[event] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[config] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[ref] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[audit] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[migration] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[archive] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[core] TO [app_execute];
GO
GRANT VIEW DEFINITION ON SCHEMA::[process] TO [app_execute];
GO
-- SELECT on views only is granted object-by-object by the generator (Views/*.sql carry their
-- own GRANT), so a hand-written table never becomes readable by accident.
