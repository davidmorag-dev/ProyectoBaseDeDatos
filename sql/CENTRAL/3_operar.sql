-- CENTRAL. Comprobar y operar. Se ejecuta cuantas veces haga falta, un bloque a la vez (F9, y los EXEC con F5).
-- Parte A: verificacion. Parte B: SUC01 y SUC02 (enlaces). Parte C: SUC03 (correo). Parte D: consolidado de los tres nodos.
SET SERVEROUTPUT ON

------------------------------------------------------------
-- PARTE A. VERIFICACION GENERAL
------------------------------------------------------------
-- 1. objetos con errores (no debe devolver filas) [se puede repetir]
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

-- 2. estado de las sucursales [se puede repetir]
SELECT codigoSucursal, modoSyncSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal FROM SUCURSAL;

------------------------------------------------------------
-- PARTE B. SUC01 Y SUC02 (conectadas por enlace)
------------------------------------------------------------
-- 3. enlaces (cada uno debe devolver 1) [se puede repetir]
SELECT 1 FROM DUAL@LNK_SUC01;

SELECT 1 FROM DUAL@LNK_SUC02;

-- 4. antes de sincronizar: lo que tiene pendiente cada sucursal [se puede repetir]
SELECT 'SUC01' AS nodo, tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA@LNK_SUC01 GROUP BY tablaOrigenSalida, estadoSalida;

SELECT 'SUC02' AS nodo, tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA@LNK_SUC02 GROUP BY tablaOrigenSalida, estadoSalida;

-- 5. sincronizar [se puede repetir]
EXEC SP_CICLO_SYNC('SUC01');

EXEC SP_CICLO_SYNC('SUC02');

EXEC SP_CICLO_SYNC('SUC01');

-- 6. bitacora (SUBIDA y BAJADA deben salir OK, DESCARTADO u OMITIDO, nunca ERROR) [se puede repetir]
SELECT contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, resultadoBitacora FROM BITACORA_SYNC ORDER BY idBitacora DESC;

-- 7. cambiar un precio en la central, sincronizar y comparar los tres nodos [se puede repetir, sube la version del precio]
EXEC SP_CAMBIAR_PRECIO(1, 455000);

EXEC SP_CICLO_SYNC('SUC01');

EXEC SP_CICLO_SYNC('SUC02');

SELECT p.idProducto, p.precioActualProducto AS central, s1.precioActualProducto AS suc01, s2.precioActualProducto AS suc02
FROM PRODUCTO p
JOIN PRODUCTO@LNK_SUC01 s1 ON s1.idProducto = p.idProducto
JOIN PRODUCTO@LNK_SUC02 s2 ON s2.idProducto = p.idProducto
ORDER BY p.idProducto;

-- 8. sincronizacion automatica cada 5 minutos para las sucursales conectadas [una sola vez] (si ya existen los trabajos da error)
BEGIN
    FOR s IN (SELECT codigoSucursal FROM SUCURSAL WHERE modoSyncSucursal = 'CONECTADO') LOOP
        DBMS_SCHEDULER.CREATE_JOB(job_name => 'JOB_SYNC_' || s.codigoSucursal, job_type => 'STORED_PROCEDURE',
            job_action => 'SP_CICLO_SYNC', number_of_arguments => 1, repeat_interval => 'FREQ=MINUTELY;INTERVAL=5', enabled => FALSE);
        DBMS_SCHEDULER.SET_JOB_ARGUMENT_VALUE('JOB_SYNC_' || s.codigoSucursal, 1, s.codigoSucursal);
        DBMS_SCHEDULER.ENABLE('JOB_SYNC_' || s.codigoSucursal);
    END LOOP;
END;
/

-- verificar estado de los trabajos (enabled TRUE = activo) [se puede repetir]
SELECT job_name, enabled, last_start_date, next_run_date FROM user_scheduler_jobs;

-- desactivar los trabajos (para que el ciclo solo corra a mano y se vea el ANTES con PENDIENTE) [se puede repetir]
EXEC DBMS_SCHEDULER.DISABLE('JOB_SYNC_SUC01');

EXEC DBMS_SCHEDULER.DISABLE('JOB_SYNC_SUC02');

-- 9. trabajos programados y su ultima ejecucion [se puede repetir]
SELECT job_name, enabled, last_start_date, next_run_date FROM user_scheduler_jobs;

------------------------------------------------------------
-- PARTE C. SUC03 (por correo)
------------------------------------------------------------
-- 10. carpeta del correo (debe devolver C:\sync) y procedimientos del correo (los tres deben salir VALID) [se puede repetir]
SELECT directory_name, directory_path FROM all_directories WHERE directory_name = 'DIR_SYNC';

SELECT object_name, status FROM user_objects WHERE object_name IN ('SP_PROCESAR_PAQUETE', 'SP_GENERAR_PAQUETE', 'FN_SIGUIENTE_PAQUETE');

-- 11. aplicar una copia alterada del lote (le cambiaron una letra a mano): se rechaza completa con ORA-20041 y la bitacora anota ERROR [se puede repetir]
EXEC SP_PROCESAR_PAQUETE('lote_SUC03_alterado.txt', 'SUC03', 'CENTRAL');

-- 12. aplicar el lote que mando SUC03 (el archivo ya esta en C:\sync) [la primera vez aplica; despues sale OMITIDO]
EXEC SP_PROCESAR_PAQUETE('lote_SUC03_0001.txt', 'SUC03', 'CENTRAL');

SELECT origenRecibido, idEnvioRecibido, resultadoRecibido FROM SYNC_RECIBIDO WHERE origenRecibido = 'SUC03' ORDER BY idEnvioRecibido;

-- 13. aplicar el mismo lote otra vez: no se duplica nada (la bitacora marca OMITIDO) [se puede repetir]
EXEC SP_PROCESAR_PAQUETE('lote_SUC03_0001.txt', 'SUC03', 'CENTRAL');

SELECT COUNT(*) AS facturasSuc03 FROM FACTURA WHERE idSucursalEmisora = 3;

-- 14. generar la respuesta para SUC03 (queda en C:\sync y se envia por correo) [una sola vez] (repetirlo genera otro paquete)
EXEC SP_GENERAR_PAQUETE('CENTRAL', 'SUC03', FN_SIGUIENTE_PAQUETE('SUC03'));

SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA WHERE destinoSalida = 'SUC03' GROUP BY tablaOrigenSalida, estadoSalida;

------------------------------------------------------------
-- PARTE D. CONSOLIDADO Y SEGUIMIENTO (los tres nodos juntos)
------------------------------------------------------------
-- 15. clientes por sucursal de origen y facturas recibidas [se puede repetir]
SELECT idSucursalOrigen, COUNT(*) AS clientes FROM CLIENTE GROUP BY idSucursalOrigen;

SELECT idFactura, idSucursalEmisora, idSucursalCliente, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;

-- 16. clientes repetidos detectados [se puede repetir]
SELECT * FROM CLIENTE_EQUIVALENCIA;

-- 17. ventas por sucursal [se puede repetir]
SELECT s.codigoSucursal, COUNT(*) AS facturas, SUM(f.totalFactura) AS totalVendido
FROM FACTURA f JOIN SUCURSAL s ON s.idSucursal = f.idSucursalEmisora
GROUP BY s.codigoSucursal ORDER BY s.codigoSucursal;

-- 18. ventas por sucursal en un periodo (cambiar las fechas) [se puede repetir]
SELECT s.codigoSucursal, COUNT(*) AS facturas, SUM(f.totalFactura) AS totalVendido
FROM FACTURA f JOIN SUCURSAL s ON s.idSucursal = f.idSucursalEmisora
WHERE f.fechaEmisionFactura BETWEEN TO_DATE('2026-11-01', 'YYYY-MM-DD') AND TO_DATE('2026-11-30', 'YYYY-MM-DD') + 1
GROUP BY s.codigoSucursal ORDER BY s.codigoSucursal;

-- 19. bloques de numeracion de facturas [se puede repetir]
SELECT idRango, idSucursal, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA ORDER BY idRango;

-- 20. pantalla de seguimiento (solo la central): lo que se movio con cada nodo, lo mas reciente primero [se puede repetir]
SELECT contraparteBitacora AS nodo, direccionBitacora AS direccion, tablaAfectadaBitacora AS tabla,
    resultadoBitacora AS resultado, TO_CHAR(fechaFinBitacora, 'YYYY-MM-DD HH24:MI:SS') AS fecha
FROM BITACORA_SYNC ORDER BY idBitacora DESC;
-- resumen por nodo y direccion
SELECT contraparteBitacora AS nodo, direccionBitacora AS direccion, resultadoBitacora AS resultado, COUNT(*) AS cantidad
FROM BITACORA_SYNC GROUP BY contraparteBitacora, direccionBitacora, resultadoBitacora ORDER BY 1, 2, 3;