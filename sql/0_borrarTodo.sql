-- Sirve para los cuatro nodos (CENTRAL, SUC01, SUC02 y SUC03). Cada quien lo ejecuta con su propio usuario.
-- Borra todo lo del proyecto para empezar de cero. Si algo no existe en ese nodo, simplemente lo salta.
-- Ejecutar como script (F5) y despues correr 1_instalar.sql.

-- trabajos programados
BEGIN
    FOR j IN (SELECT job_name FROM user_scheduler_jobs) LOOP
        DBMS_SCHEDULER.DROP_JOB(j.job_name, TRUE);
    END LOOP;
END;
/

-- enlaces de base de datos (solo la central los tiene)
BEGIN
    FOR l IN (SELECT db_link FROM user_db_links) LOOP
        EXECUTE IMMEDIATE 'DROP DATABASE LINK ' || l.db_link;
    END LOOP;
END;
/

-- procedimientos y funciones
BEGIN
    FOR o IN (SELECT object_name, object_type FROM user_objects WHERE object_type IN ('PROCEDURE', 'FUNCTION')) LOOP
        EXECUTE IMMEDIATE 'DROP ' || o.object_type || ' ' || o.object_name;
    END LOOP;
END;
/

-- tablas
BEGIN
    FOR t IN (SELECT table_name FROM user_tables
              WHERE table_name IN ('BITACORA_SYNC', 'SYNC_RECIBIDO', 'SYNC_SALIDA', 'DETALLE_FACTURA', 'FACTURA',
                                   'RANGO_FACTURA', 'CLIENTE_EQUIVALENCIA', 'CLIENTE', 'PRODUCTO', 'SUCURSAL')) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS';
    END LOOP;
END;
/

-- comprobar que no quedo nada (las dos consultas deben devolver 0 filas)
SELECT table_name FROM user_tables;
SELECT object_name, object_type FROM user_objects WHERE object_type IN ('PROCEDURE', 'FUNCTION');
