-- SUC03. Comprobar y operar. Se ejecuta cuantas veces haga falta, un bloque a la vez (F9, y los EXEC con F5).
SET SERVEROUTPUT ON

------------------------------------------------------------
-- PARTE A. VERIFICACION Y DATOS INICIALES
------------------------------------------------------------
-- 1. objetos con errores (no debe devolver filas) [se puede repetir]
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

-- 2. datos iniciales [se puede repetir]
SELECT 'PRODUCTO' AS tabla, COUNT(*) AS filas FROM PRODUCTO
UNION ALL SELECT 'CLIENTE', COUNT(*) FROM CLIENTE
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA;

-- 3. bloque de numeracion propio [se puede repetir]
SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA;

------------------------------------------------------------
-- PARTE B. ANTES DE ENVIAR (facturar y dejar envios PENDIENTE)
------------------------------------------------------------
-- 4. facturar (funciona aunque la central este apagada). El detalle va como producto:cantidad;producto:cantidad [una sola vez] (cada vez crea facturas nuevas)
VARIABLE idFactura NUMBER
-- Jorge Castro Perez
EXEC SP_EMITIR_FACTURA(3, 3, 1, '7:1;8:2', :idFactura);
PRINT idFactura

-- Laura Solis Vega
EXEC SP_EMITIR_FACTURA(3, 3, 2, '6:1;9:1', :idFactura);
PRINT idFactura

-- 5. facturas emitidas y envios pendientes hacia la central [se puede repetir]
SELECT idFactura, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;

SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

-- 6. guardar un cliente nuevo (queda pendiente para la central) [una sola vez] (repetirlo sube la version del cliente)
EXEC SP_GUARDAR_CLIENTE(3, 3, 'CEDULA', '909990999', 'Mario Salas Arce');

------------------------------------------------------------
-- PARTE C. CORREO: generar el lote y aplicar la respuesta de la central
------------------------------------------------------------
-- 7. carpeta del correo (debe devolver C:\sync) [se puede repetir]
SELECT directory_name, directory_path FROM all_directories WHERE directory_name = 'DIR_SYNC';

-- 8. generar el lote para la central (queda en C:\sync y se envia por correo) [una sola vez] (repetirlo genera otro lote)
EXEC SP_GENERAR_PAQUETE('SUC03', 'CENTRAL', FN_SIGUIENTE_PAQUETE('CENTRAL'));

-- 9. despues de generar los envios quedan ENVIADO, y APLICADO cuando llega el acuse [se puede repetir]
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

-- 10. aplicar la respuesta de la central (el archivo ya esta en C:\sync) [se puede repetir]
EXEC SP_PROCESAR_PAQUETE('respuesta_SUC03_0001.txt', 'CENTRAL', 'SUC03');

-- 11. aplicar la misma respuesta otra vez: no cambia nada [se puede repetir]
EXEC SP_PROCESAR_PAQUETE('respuesta_SUC03_0001.txt', 'CENTRAL', 'SUC03');

SELECT origenRecibido, resultadoRecibido, COUNT(*) AS cantidad FROM SYNC_RECIBIDO GROUP BY origenRecibido, resultadoRecibido;

------------------------------------------------------------
-- PARTE D. LO QUE ENTREGO LA CENTRAL
------------------------------------------------------------
-- 12. precios y clientes recibidos [se puede repetir]
SELECT idProducto, precioActualProducto FROM PRODUCTO ORDER BY idProducto;

SELECT idSucursalOrigen, COUNT(*) AS clientes FROM CLIENTE GROUP BY idSucursalOrigen;

-- 13. trabajo programado: JOB_LOTE_SUC03 genera el lote solo todos los dias a las 20:00 (enabled TRUE = activo) [se puede repetir]
SELECT job_name, enabled, last_start_date, next_run_date FROM user_scheduler_jobs;
