-- Ejecutar en SUC03.
-- Un bloque a la vez (F9).
SET SERVEROUTPUT ON

-- 1. Confirmar el usuario y el servicio
SELECT USER AS usuario, SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS servicio, SYS_CONTEXT('USERENV', 'SERVER_HOST') AS equipo FROM DUAL;

-- 2. Las 10 tablas del proyecto (debe devolver 10 filas)
SELECT table_name FROM user_tables
WHERE table_name IN ('SUCURSAL', 'PRODUCTO', 'CLIENTE', 'CLIENTE_EQUIVALENCIA', 'RANGO_FACTURA',
                     'FACTURA', 'DETALLE_FACTURA', 'SYNC_SALIDA', 'SYNC_RECIBIDO', 'BITACORA_SYNC')
ORDER BY table_name;

-- 3. Datos iniciales
SELECT 'SUCURSAL' AS tabla, COUNT(*) AS filas FROM SUCURSAL
UNION ALL SELECT 'PRODUCTO', COUNT(*) FROM PRODUCTO
UNION ALL SELECT 'RANGO_FACTURA', COUNT(*) FROM RANGO_FACTURA
UNION ALL SELECT 'CLIENTE', COUNT(*) FROM CLIENTE
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA;

-- 4. Bloque de facturas propio (del 2001 al 3000, ACTIVO)
SELECT idRango, idSucursal, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA ORDER BY idRango;

-- 5. Procedimientos de facturacion y del correo (todos deben salir VALID)
SELECT object_name, object_type, status FROM user_objects
WHERE object_name IN ('SP_SOLICITAR_BLOQUE', 'SP_EMITIR_FACTURA', 'SP_RETIRAR_BLOQUE', 'SP_GUARDAR_CLIENTE',
                      'SP_REGISTRAR_BITACORA', 'FN_SERIALIZAR', 'FN_SIGUIENTE_LOTE', 'FN_HUELLA', 'SP_GENERAR_LOTE')
ORDER BY object_name;

-- 6. Objetos con errores (no debe devolver filas)
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

-- 7. Carpeta del correo (debe devolver C:\sync)
SELECT directory_name, directory_path FROM all_directories WHERE directory_name = 'DIR_SYNC';

-- 8. Probar que Oracle puede escribir en C:\sync
DECLARE
    archivo UTL_FILE.FILE_TYPE;
BEGIN
    archivo := UTL_FILE.FOPEN('DIR_SYNC', 'prueba_suc03.txt', 'W');
    UTL_FILE.PUT_LINE(archivo, 'Prueba de SUC03 ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
    UTL_FILE.FCLOSE(archivo);
    DBMS_OUTPUT.PUT_LINE('DIR_SYNC funciona');
END;
/

-- 9. Permiso para el trabajo automatico
SELECT privilege FROM user_sys_privs WHERE privilege = 'CREATE JOB';

-- 10. Trabajo que genera el lote a las 8 p. m.
SELECT job_name, enabled, state, next_run_date FROM user_scheduler_jobs;

-- 11. Factura de prueba para tener algo que mandar
VARIABLE idFactura NUMBER
EXEC SP_EMITIR_FACTURA(3, 3, 1, '[{"idProducto":1,"cantidad":1}]', :idFactura);
PRINT idFactura

-- 12. Envios pendientes hacia CENTRAL
SELECT idSalida, tablaOrigenSalida, claveRegistroSalida, estadoSalida FROM SYNC_SALIDA WHERE destinoSalida = 'CENTRAL' ORDER BY idSalida;

-- 13. Numero que tendra el proximo lote
SELECT FN_SIGUIENTE_LOTE AS proximoLote FROM DUAL;

-- 14. Generar el lote
EXEC SP_GENERAR_LOTE(FN_SIGUIENTE_LOTE);

-- 15. Despues de generar: ENVIADO
SELECT estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA WHERE destinoSalida = 'CENTRAL' GROUP BY estadoSalida;

-- 16. Registro de lotes generados (LOTE_GEN debe salir OK)
SELECT direccionBitacora, tablaAfectadaBitacora, fechaInicioBitacora, resultadoBitacora
FROM BITACORA_SYNC ORDER BY idBitacora DESC FETCH FIRST 10 ROWS ONLY;


-- RESPUESTA DE LA CENTRAL

-- 17. Procedimientos de la respuesta (deben salir VALID)
SELECT object_name, object_type, status FROM user_objects
WHERE object_name IN ('FN_CAMPO', 'SP_PROCESAR_RESPUESTA') ORDER BY object_name;

-- 18. Conteos antes de aplicar
SELECT (SELECT COUNT(*) FROM CLIENTE) AS clientes,
       (SELECT COUNT(*) FROM SYNC_RECIBIDO WHERE origenRecibido = 'CENTRAL') AS recibidosCentral,
       (SELECT COUNT(*) FROM SYNC_SALIDA WHERE destinoSalida = 'CENTRAL' AND estadoSalida = 'APLICADO') AS enviosConfirmados
FROM DUAL;

-- 19. Aplicar la respuesta
EXEC SP_PROCESAR_RESPUESTA('respuesta_SUC03_0001.txt', 'SUC03');

-- 20. Conteos despues de aplicar
SELECT (SELECT COUNT(*) FROM CLIENTE) AS clientes,
       (SELECT COUNT(*) FROM SYNC_RECIBIDO WHERE origenRecibido = 'CENTRAL') AS recibidosCentral,
       (SELECT COUNT(*) FROM SYNC_SALIDA WHERE destinoSalida = 'CENTRAL' AND estadoSalida = 'APLICADO') AS enviosConfirmados
FROM DUAL;

-- 21. Envios de la central recibidos y su resultado (APLICADO o DESCARTADO)
SELECT idEnvioRecibido, fechaRecepcionRecibido, resultadoRecibido FROM SYNC_RECIBIDO
WHERE origenRecibido = 'CENTRAL' ORDER BY idEnvioRecibido;

-- 22. Precios actuales
SELECT idProducto, precioActualProducto, fechaModificacionProducto FROM PRODUCTO ORDER BY idProducto;

-- 23. Aplicar otra vez y repetir 18: sin cambios
EXEC SP_PROCESAR_RESPUESTA('respuesta_SUC03_0001.txt', 'SUC03');
