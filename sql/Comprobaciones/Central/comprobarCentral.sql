-- Ejecutar solo en CENTRAL. Cada bloque se corre por separado (seleccionar y F9) para ir comprobando.
SET SERVEROUTPUT ON

-- 1. Confirmar que se esta en el nodo correcto (usuario CENTRAL, servicio XEPDB1)
SELECT USER AS usuario, SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS servicio, SYS_CONTEXT('USERENV', 'SERVER_HOST') AS equipo FROM DUAL;

-- 2. Las 10 tablas del proyecto (debe devolver 10 filas)
SELECT table_name FROM user_tables
WHERE table_name IN ('SUCURSAL', 'PRODUCTO', 'CLIENTE', 'CLIENTE_EQUIVALENCIA', 'RANGO_FACTURA',
                     'FACTURA', 'DETALLE_FACTURA', 'SYNC_SALIDA', 'SYNC_RECIBIDO', 'BITACORA_SYNC')
ORDER BY table_name;

-- 3. Datos iniciales (SUCURSAL 3, PRODUCTO 10, RANGO_FACTURA 3 o mas)
SELECT 'SUCURSAL' AS tabla, COUNT(*) AS filas FROM SUCURSAL
UNION ALL SELECT 'PRODUCTO', COUNT(*) FROM PRODUCTO
UNION ALL SELECT 'RANGO_FACTURA', COUNT(*) FROM RANGO_FACTURA
UNION ALL SELECT 'CLIENTE', COUNT(*) FROM CLIENTE
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA;

-- 4. Sucursales y su modo (SUC01 y SUC02 CONECTADO, SUC03 DIFERIDO)
SELECT idSucursal, codigoSucursal, modoSyncSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal FROM SUCURSAL ORDER BY idSucursal;

-- 5. Procedimientos y funciones de la central (todos deben salir VALID)
SELECT object_name, object_type, status FROM user_objects
WHERE object_name IN ('SP_REGISTRAR_BITACORA', 'SP_CONSOLIDAR_CLIENTE', 'SP_ASIGNAR_BLOQUE', 'SP_APLICAR_SUBIDA',
                      'SP_APLICAR_BAJADA', 'SP_CICLO_SYNC', 'SP_CAMBIAR_PRECIO', 'FN_CAMPO', 'FN_HUELLA', 'SP_PROCESAR_LOTE')
ORDER BY object_name;

-- 6. Objetos con errores (no debe devolver filas)
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

-- 7. Enlaces creados (deben aparecer LNK_SUC01 y LNK_SUC02 con su IP)
SELECT db_link, username, host FROM user_db_links;

-- 8. Probar cada enlace (cada uno debe devolver 1)
SELECT 1 FROM DUAL@LNK_SUC01;
SELECT 1 FROM DUAL@LNK_SUC02;

-- 9. Ver que cada sucursal tenga sus tablas (debe devolver 10 en cada una)
SELECT COUNT(*) AS tablasSuc01 FROM user_tables@LNK_SUC01;
SELECT COUNT(*) AS tablasSuc02 FROM user_tables@LNK_SUC02;

-- 10. Carpeta del correo de SUC03 (debe devolver C:\sync)
SELECT directory_name, directory_path FROM all_directories WHERE directory_name = 'DIR_SYNC';

-- 11. Probar que Oracle puede escribir en C:\sync (debe crear C:\sync\prueba_central.txt)
DECLARE
    archivo UTL_FILE.FILE_TYPE;
BEGIN
    archivo := UTL_FILE.FOPEN('DIR_SYNC', 'prueba_central.txt', 'W');
    UTL_FILE.PUT_LINE(archivo, 'Prueba de CENTRAL ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
    UTL_FILE.FCLOSE(archivo);
    DBMS_OUTPUT.PUT_LINE('DIR_SYNC funciona');
END;
/

-- 12. Ver si el lote de SUC03 ya esta en C:\sync antes de procesarlo
DECLARE
    existe BOOLEAN;
    tamano NUMBER;
    bloque BINARY_INTEGER;
BEGIN
    UTL_FILE.FGETATTR('DIR_SYNC', 'lote_SUC03_0001.txt', existe, tamano, bloque);
    IF existe THEN
        DBMS_OUTPUT.PUT_LINE('Lote encontrado: ' || tamano || ' bytes');
    ELSE
        DBMS_OUTPUT.PUT_LINE('El lote no esta en C:\sync');
    END IF;
END;
/

-- 13. Procesar el lote de SUC03 (correrlo dos veces no debe duplicar datos)
EXEC SP_PROCESAR_LOTE('lote_SUC03_0001.txt', 'SUC03');

-- 14. Envios recibidos por sucursal y su resultado
SELECT origenRecibido, resultadoRecibido, COUNT(*) AS cantidad FROM SYNC_RECIBIDO GROUP BY origenRecibido, resultadoRecibido ORDER BY origenRecibido;

-- 15. Facturas recibidas por sucursal emisora
SELECT idSucursalEmisora, COUNT(*) AS facturas, SUM(totalFactura) AS total FROM FACTURA GROUP BY idSucursalEmisora ORDER BY idSucursalEmisora;

-- 16. Envios de la central que siguen pendientes hacia cada sucursal
SELECT destinoSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY destinoSalida, estadoSalida ORDER BY destinoSalida;

-- 17. Ultimos movimientos de sincronizacion (no debe haber ERROR)
SELECT contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, fechaInicioBitacora, resultadoBitacora
FROM BITACORA_SYNC ORDER BY idBitacora DESC FETCH FIRST 20 ROWS ONLY;

-- 18. Trabajos automaticos (JOB_SYNC_SUC01 y JOB_SYNC_SUC02, si ya se programaron)
SELECT job_name, enabled, state, last_start_date, next_run_date FROM user_scheduler_jobs;
