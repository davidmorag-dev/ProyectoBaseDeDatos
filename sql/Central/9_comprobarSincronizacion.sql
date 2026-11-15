-- Ejecutar solo en CENTRAL. Cada bloque se corre por separado (seleccionar y F9 o F5) para ir comprobando.

-- 1. Comprobar que los enlaces conectan (cada uno debe devolver 1)
SELECT 1 FROM DUAL@LNK_SUC01;
SELECT 1 FROM DUAL@LNK_SUC02;

-- 2. Ejecutar el ciclo de sincronizacion de cada sucursal conectada
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');

-- 3. Ver lo que registro cada ciclo (SUBIDA y BAJADA deben salir OK o DESCARTADO)
SELECT * FROM BITACORA_SYNC ORDER BY fechaInicioBitacora DESC;

-- 4. Facturas recibidas en la central
SELECT idFactura, idSucursalEmisora, idSucursalCliente, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;

-- 5. Clientes recibidos por sucursal de origen
SELECT idSucursalOrigen, COUNT(*) AS clientes FROM CLIENTE GROUP BY idSucursalOrigen;

-- 6. Clientes duplicados detectados (por ejemplo Maria Rojas Mora)
SELECT * FROM CLIENTE_EQUIVALENCIA;

-- 7. Envios de la central que siguen pendientes hacia las sucursales
SELECT destinoSalida, tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY destinoSalida, tablaOrigenSalida, estadoSalida;

-- 8. Bloques de numeracion de factura por sucursal
SELECT * FROM RANGO_FACTURA ORDER BY idRango;

-- 9. Estado de conexion y ultima sincronizacion de cada sucursal
SELECT codigoSucursal, modoSyncSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal FROM SUCURSAL;

-- 10. Procesar el lote por correo de SUC03 (el archivo debe estar en C:\sync)
EXEC SP_PROCESAR_LOTE('lote_SUC03_0001.txt', 'SUC03');

-- 11. Lotes recibidos de SUC03 y su resultado
SELECT * FROM SYNC_RECIBIDO ORDER BY idRecibido;

-- 12. Trabajos automaticos (cada 5 minutos) y su ultima ejecucion
SELECT job_name, enabled, last_start_date, next_run_date FROM user_scheduler_jobs;

-- 13. Objetos con errores (no debe devolver filas)
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';
