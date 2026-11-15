-- Ejecutar en CENTRAL despues de 5_sincronizarCentral.sql.
-- Ejecuta SP_CICLO_SYNC cada 5 minutos para SUC01 y SUC02.

BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name            => 'JOB_SYNC_SUC01',
        job_type            => 'STORED_PROCEDURE',
        job_action          => 'SP_CICLO_SYNC',
        number_of_arguments => 1,
        repeat_interval     => 'FREQ=MINUTELY;INTERVAL=5',
        enabled             => FALSE);
    DBMS_SCHEDULER.SET_JOB_ARGUMENT_VALUE('JOB_SYNC_SUC01', 1, 'SUC01');
    DBMS_SCHEDULER.ENABLE('JOB_SYNC_SUC01');
END;
/

BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name            => 'JOB_SYNC_SUC02',
        job_type            => 'STORED_PROCEDURE',
        job_action          => 'SP_CICLO_SYNC',
        number_of_arguments => 1,
        repeat_interval     => 'FREQ=MINUTELY;INTERVAL=5',
        enabled             => FALSE);
    DBMS_SCHEDULER.SET_JOB_ARGUMENT_VALUE('JOB_SYNC_SUC02', 1, 'SUC02');
    DBMS_SCHEDULER.ENABLE('JOB_SYNC_SUC02');
END;
/

-- EXEC DBMS_SCHEDULER.RUN_JOB('JOB_SYNC_SUC01');
-- EXEC DBMS_SCHEDULER.DISABLE('JOB_SYNC_SUC01');
-- SELECT job_name, enabled, last_start_date, next_run_date FROM USER_SCHEDULER_JOBS;
