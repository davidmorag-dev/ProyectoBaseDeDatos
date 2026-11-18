-- CENTRAL. Comprobar y operar. Se ejecuta cuantas veces haga falta, un bloque a la vez (F9, y los EXEC con F5).
SET SERVEROUTPUT ON

-- 1. objetos con errores (no debe devolver filas)
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

-- 2. enlaces (cada uno debe devolver 1)
SELECT 1 FROM DUAL@LNK_SUC01;
SELECT 1 FROM DUAL@LNK_SUC02;

-- 3. estado de las sucursales
SELECT codigoSucursal, modoSyncSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal FROM SUCURSAL;

-- 4. antes de sincronizar: lo que tiene pendiente cada sucursal
SELECT 'SUC01' AS nodo, tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA@LNK_SUC01 GROUP BY tablaOrigenSalida, estadoSalida;
SELECT 'SUC02' AS nodo, tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA@LNK_SUC02 GROUP BY tablaOrigenSalida, estadoSalida;

-- 5. sincronizar
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');

-- 6. bitacora (SUBIDA y BAJADA deben salir OK, DESCARTADO u OMITIDO, nunca ERROR)
SELECT contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, resultadoBitacora FROM BITACORA_SYNC ORDER BY idBitacora DESC;

-- 7. despues de sincronizar: clientes por sucursal de origen y facturas recibidas
SELECT idSucursalOrigen, COUNT(*) AS clientes FROM CLIENTE GROUP BY idSucursalOrigen;
SELECT idFactura, idSucursalEmisora, idSucursalCliente, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;

-- 8. clientes repetidos detectados
SELECT * FROM CLIENTE_EQUIVALENCIA;

-- 9. consolidado: ventas por sucursal
SELECT s.codigoSucursal, COUNT(*) AS facturas, SUM(f.totalFactura) AS totalVendido
FROM FACTURA f JOIN SUCURSAL s ON s.idSucursal = f.idSucursalEmisora
GROUP BY s.codigoSucursal ORDER BY s.codigoSucursal;

-- 10. ventas por sucursal en un periodo (cambiar las fechas)
SELECT s.codigoSucursal, COUNT(*) AS facturas, SUM(f.totalFactura) AS totalVendido
FROM FACTURA f JOIN SUCURSAL s ON s.idSucursal = f.idSucursalEmisora
WHERE f.fechaEmisionFactura BETWEEN TO_DATE('2026-11-01', 'YYYY-MM-DD') AND TO_DATE('2026-11-30', 'YYYY-MM-DD') + 1
GROUP BY s.codigoSucursal ORDER BY s.codigoSucursal;

-- 11. bloques de numeracion de facturas
SELECT idRango, idSucursal, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA ORDER BY idRango;

-- 12. cambiar un precio en la central, sincronizar y comparar los tres nodos
EXEC SP_CAMBIAR_PRECIO(1, 455000);
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');
SELECT p.idProducto, p.precioActualProducto AS central, s1.precioActualProducto AS suc01, s2.precioActualProducto AS suc02
FROM PRODUCTO p
JOIN PRODUCTO@LNK_SUC01 s1 ON s1.idProducto = p.idProducto
JOIN PRODUCTO@LNK_SUC02 s2 ON s2.idProducto = p.idProducto
ORDER BY p.idProducto;

-- 13. sincronizacion automatica cada 5 minutos para las sucursales conectadas
BEGIN
    FOR s IN (SELECT codigoSucursal FROM SUCURSAL WHERE modoSyncSucursal = 'CONECTADO') LOOP
        DBMS_SCHEDULER.CREATE_JOB(job_name => 'JOB_SYNC_' || s.codigoSucursal, job_type => 'STORED_PROCEDURE',
            job_action => 'SP_CICLO_SYNC', number_of_arguments => 1, repeat_interval => 'FREQ=MINUTELY;INTERVAL=5', enabled => FALSE);
        DBMS_SCHEDULER.SET_JOB_ARGUMENT_VALUE('JOB_SYNC_' || s.codigoSucursal, 1, s.codigoSucursal);
        DBMS_SCHEDULER.ENABLE('JOB_SYNC_' || s.codigoSucursal);
    END LOOP;
END;
/

-- 14. trabajos programados y su ultima ejecucion
SELECT job_name, enabled, last_start_date, next_run_date FROM user_scheduler_jobs;

-- 15. SUC03 por correo: carpeta del correo (debe devolver C:\sync)
SELECT directory_name, directory_path FROM all_directories WHERE directory_name = 'DIR_SYNC';

-- 16. aplicar el lote que mando SUC03 (el archivo ya esta en C:\sync)
EXEC SP_PROCESAR_PAQUETE('lote_SUC03_0001.txt', 'SUC03', 'CENTRAL');
SELECT origenRecibido, idEnvioRecibido, resultadoRecibido FROM SYNC_RECIBIDO WHERE origenRecibido = 'SUC03' ORDER BY idEnvioRecibido;

-- 17. aplicar el mismo lote otra vez: no se duplica nada (la bitacora marca OMITIDO)
EXEC SP_PROCESAR_PAQUETE('lote_SUC03_0001.txt', 'SUC03', 'CENTRAL');
SELECT COUNT(*) AS facturasSuc03 FROM FACTURA WHERE idSucursalEmisora = 3;

-- 18. generar la respuesta para SUC03 (queda en C:\sync y se envia por correo)
EXEC SP_GENERAR_PAQUETE('CENTRAL', 'SUC03', FN_SIGUIENTE_PAQUETE('SUC03'));
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA WHERE destinoSalida = 'SUC03' GROUP BY tablaOrigenSalida, estadoSalida;
