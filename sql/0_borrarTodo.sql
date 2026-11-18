-- Sirve para los cuatro nodos (CENTRAL, SUC01, SUC02 y SUC03). Cada quien lo ejecuta con su propio usuario.
-- Borra todo lo del proyecto para empezar de cero y muestra lo que borro o el error si algo falla.
-- Ejecutar completo con F5 (ejecutar como script) y despues correr 1_instalar.sql.

SET SERVEROUTPUT ON

-- quien soy (debe ser el usuario de este nodo)
SELECT USER AS usuario FROM DUAL;

DECLARE
    -- ejecuta una sentencia y dice si funciono
    PROCEDURE borrar (pSentencia IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE pSentencia;
        DBMS_OUTPUT.PUT_LINE('OK     ' || pSentencia);
    EXCEPTION WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('ERROR  ' || pSentencia || ' -> ' || SQLERRM);
    END;
BEGIN
    -- trabajos programados
    FOR j IN (SELECT job_name FROM user_scheduler_jobs) LOOP
        borrar('BEGIN DBMS_SCHEDULER.DROP_JOB(''' || j.job_name || ''', TRUE); END;');
    END LOOP;

    -- enlaces de base de datos (solo la central los tiene)
    FOR l IN (SELECT db_link FROM user_db_links) LOOP
        borrar('DROP DATABASE LINK ' || l.db_link);
    END LOOP;

    -- procedimientos y funciones
    FOR o IN (SELECT object_name, object_type FROM user_objects WHERE object_type IN ('PROCEDURE', 'FUNCTION')) LOOP
        borrar('DROP ' || o.object_type || ' ' || o.object_name);
    END LOOP;

    -- tablas del proyecto
    FOR t IN (SELECT table_name FROM user_tables
              WHERE table_name IN ('BITACORA_SYNC', 'SYNC_RECIBIDO', 'SYNC_SALIDA', 'DETALLE_FACTURA', 'FACTURA',
                                   'RANGO_FACTURA', 'CLIENTE_EQUIVALENCIA', 'CLIENTE', 'PRODUCTO', 'SUCURSAL')) LOOP
        borrar('DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE');
    END LOOP;

    borrar('PURGE RECYCLEBIN');
END;
/

-- lo que queda (los cuatro numeros deben ser 0)
SELECT 'tablas del proyecto' AS revision, COUNT(*) AS cantidad FROM user_tables
WHERE table_name IN ('BITACORA_SYNC', 'SYNC_RECIBIDO', 'SYNC_SALIDA', 'DETALLE_FACTURA', 'FACTURA',
                     'RANGO_FACTURA', 'CLIENTE_EQUIVALENCIA', 'CLIENTE', 'PRODUCTO', 'SUCURSAL')
UNION ALL SELECT 'procedimientos y funciones', COUNT(*) FROM user_objects WHERE object_type IN ('PROCEDURE', 'FUNCTION')
UNION ALL SELECT 'enlaces', COUNT(*) FROM user_db_links
UNION ALL SELECT 'trabajos programados', COUNT(*) FROM user_scheduler_jobs;


DROP DATABASE LINK LNK_SUC01;
DROP DATABASE LINK LNK_SUC02;

