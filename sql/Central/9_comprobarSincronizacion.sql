-- Ejecutar en CENTRAL, un bloque a la vez.

-- 1. Probar los enlaces
SELECT 1 FROM DUAL@LNK_SUC01;
SELECT 1 FROM DUAL@LNK_SUC02;

-- 2. Ciclo de cada sucursal
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');

-- 3. Bitacora de los ciclos
SELECT * FROM BITACORA_SYNC ORDER BY fechaInicioBitacora DESC;

-- 4. Facturas recibidas en la central
SELECT idFactura, idSucursalEmisora, idSucursalCliente, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;

-- 5. Clientes recibidos por sucursal de origen
SELECT idSucursalOrigen, COUNT(*) AS clientes FROM CLIENTE GROUP BY idSucursalOrigen;

-- 6. Clientes repetidos
SELECT * FROM CLIENTE_EQUIVALENCIA;

-- 7. Envios pendientes hacia las sucursales
SELECT destinoSalida, tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY destinoSalida, tablaOrigenSalida, estadoSalida;

-- 8. Bloques de facturas
SELECT * FROM RANGO_FACTURA ORDER BY idRango;

-- 9. Estado de cada sucursal
SELECT codigoSucursal, modoSyncSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal FROM SUCURSAL;

-- 10. Procesar el lote de SUC03
EXEC SP_PROCESAR_LOTE('lote_SUC03_0001.txt', 'SUC03');

-- 11. Envios recibidos
SELECT * FROM SYNC_RECIBIDO ORDER BY idRecibido;

-- 12. Trabajos automaticos
SELECT job_name, enabled, last_start_date, next_run_date FROM user_scheduler_jobs;

-- 13. Objetos con errores
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';
