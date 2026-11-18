-- SUC03. Comprobar y operar. Se ejecuta cuantas veces haga falta, un bloque a la vez (F9, y los EXEC con F5).
SET SERVEROUTPUT ON

-- 1. objetos con errores (no debe devolver filas)
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

-- 2. datos iniciales
SELECT 'PRODUCTO' AS tabla, COUNT(*) AS filas FROM PRODUCTO
UNION ALL SELECT 'CLIENTE', COUNT(*) FROM CLIENTE
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA;

-- 3. bloque de numeracion propio
SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA;

-- 4. facturar (funciona aunque la central este apagada). El detalle va como producto:cantidad;producto:cantidad
VARIABLE idFactura NUMBER
-- Jorge Castro Perez
EXEC SP_EMITIR_FACTURA(3, 3, 1, '7:1;8:2', :idFactura);
PRINT idFactura

-- Laura Solis Vega
EXEC SP_EMITIR_FACTURA(3, 3, 2, '6:1;9:1', :idFactura);
PRINT idFactura

-- 5. facturas emitidas y envios pendientes hacia la central
SELECT idFactura, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

-- 6. guardar un cliente nuevo (queda pendiente para la central)
EXEC SP_GUARDAR_CLIENTE(3, 3, 'CEDULA', '909990999', 'Mario Salas Arce');

-- 7. carpeta del correo (debe devolver C:\sync)
SELECT directory_name, directory_path FROM all_directories WHERE directory_name = 'DIR_SYNC';

-- 8. generar el lote para la central (queda en C:\sync y se envia por correo)
EXEC SP_GENERAR_PAQUETE('SUC03', 'CENTRAL', FN_SIGUIENTE_PAQUETE('CENTRAL'));

-- 9. despues de generar los envios quedan ENVIADO, y APLICADO cuando llega el acuse
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

-- 10. aplicar la respuesta de la central (el archivo ya esta en C:\sync)
EXEC SP_PROCESAR_PAQUETE('respuesta_SUC03_0001.txt', 'CENTRAL', 'SUC03');

-- 11. aplicar la misma respuesta otra vez: no cambia nada
EXEC SP_PROCESAR_PAQUETE('respuesta_SUC03_0001.txt', 'CENTRAL', 'SUC03');
SELECT origenRecibido, resultadoRecibido, COUNT(*) AS cantidad FROM SYNC_RECIBIDO GROUP BY origenRecibido, resultadoRecibido;

-- 12. precios y clientes recibidos
SELECT idProducto, precioActualProducto FROM PRODUCTO ORDER BY idProducto;
SELECT idSucursalOrigen, COUNT(*) AS clientes FROM CLIENTE GROUP BY idSucursalOrigen;
