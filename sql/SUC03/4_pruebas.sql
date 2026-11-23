-- SUC03. Pruebas de comportamiento del modo por correo. Se ejecuta despues de 3_operar.sql.
-- Un bloque a la vez (F9, y los EXEC con F5). Los pasos de la central estan en CENTRAL/3_operar.sql, bloques 10 a 14.
SET SERVEROUTPUT ON

------------------------------------------------------------
-- PRUEBA 1. FACTURAR SIN RED: la factura queda local y su envio PENDIENTE
------------------------------------------------------------
SELECT COUNT(*) AS facturas FROM FACTURA;

VARIABLE idFactura NUMBER
EXEC SP_EMITIR_FACTURA(3, 3, 1, '2:1;5:3', :idFactura);
PRINT idFactura

SELECT idFactura, totalFactura FROM FACTURA ORDER BY idFactura DESC FETCH FIRST 2 ROWS ONLY;
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

------------------------------------------------------------
-- PRUEBA 2. REGISTROS RECHAZADOS: no queda una factura a medias
------------------------------------------------------------
SELECT COUNT(*) AS facturas FROM FACTURA;
-- cantidad cero (ORA-02290)
EXEC SP_EMITIR_FACTURA(3, 3, 1, '1:0', :idFactura);
-- producto que no existe (ORA-01403)
EXEC SP_EMITIR_FACTURA(3, 3, 1, '99:1', :idFactura);
-- borrar un cliente que ya tiene facturas (ORA-02292)
DELETE FROM CLIENTE WHERE idSucursalOrigen = 3 AND idClienteLocal = 1;
-- los conteos no cambiaron
SELECT COUNT(*) AS facturas FROM FACTURA;

------------------------------------------------------------
-- PRUEBA 3. MODIFICAR UN CLIENTE: sube la version y viaja a la central en el siguiente lote
------------------------------------------------------------
EXEC SP_GUARDAR_CLIENTE(3, 2, 'CEDULA', '707770777', 'Cliente Modificado SUC03');
SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 3 ORDER BY idClienteLocal;
-- todos los clientes que tiene esta sucursal (propios y recibidos en la respuesta de la central) con su origen
SELECT s.codigoSucursal AS origen, c.idClienteLocal, c.numeroIdentificacionCliente AS cedula, c.nombreCliente, c.versionCliente
FROM CLIENTE c JOIN SUCURSAL s ON s.idSucursal = c.idSucursalOrigen
ORDER BY c.nombreCliente, s.codigoSucursal;

------------------------------------------------------------
-- PRUEBA 4. LOTE QUE LLEGA ALTERADO: la central lo rechaza completo
------------------------------------------------------------
-- a) generar el lote (queda en C:\sync) y ver que los envios pasan a ENVIADO
EXEC SP_GENERAR_PAQUETE('SUC03', 'CENTRAL', FN_SIGUIENTE_PAQUETE('CENTRAL'));
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

-- b) hacer una copia del lote y cambiarle una letra a mano con el Bloc de notas (por ejemplo lote_SUC03_alterado.txt)
-- c) EN CENTRAL (3_operar.sql, bloque 11): aplicar la copia alterada. Debe dar ORA-20041 y la bitacora anota ERROR; no se aplica nada
--    EXEC SP_PROCESAR_PAQUETE('lote_SUC03_alterado.txt', 'SUC03', 'CENTRAL');
-- d) EN CENTRAL (3_operar.sql, bloque 12): aplicar el lote integro. Debe quedar OK
--    EXEC SP_PROCESAR_PAQUETE('lote_SUC03_0001.txt', 'SUC03', 'CENTRAL');

------------------------------------------------------------
-- PRUEBA 5. EL MISMO LOTE DOS VECES: no se duplica nada
------------------------------------------------------------
-- EN CENTRAL: aplicar otra vez el mismo lote. La bitacora marca OMITIDO y los conteos no cambian
--    EXEC SP_PROCESAR_PAQUETE('lote_SUC03_0001.txt', 'SUC03', 'CENTRAL');

------------------------------------------------------------
-- PRUEBA 6. ACUSE: la respuesta de la central marca los envios como APLICADO
------------------------------------------------------------
-- EN CENTRAL: generar la respuesta (CENTRAL/3_operar.sql, bloque 14) y pasarla a C:\sync de SUC03 por correo
EXEC SP_PROCESAR_PAQUETE('respuesta_SUC03_0001.txt', 'CENTRAL', 'SUC03');
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;
SELECT origenRecibido, resultadoRecibido, COUNT(*) AS cantidad FROM SYNC_RECIBIDO GROUP BY origenRecibido, resultadoRecibido;

------------------------------------------------------------
-- PRUEBA 7. CAMBIOS FUERA DE ORDEN: la version mas nueva se conserva aunque el lote viejo llegue despues
------------------------------------------------------------
-- a) version 2 del cliente 1 y su lote
EXEC SP_GUARDAR_CLIENTE(3, 1, 'CEDULA', '606660666', 'Jorge Castro Perez V2');

EXEC SP_GENERAR_PAQUETE('SUC03', 'CENTRAL', FN_SIGUIENTE_PAQUETE('CENTRAL'));

-- b) version 3 del mismo cliente y otro lote (los dos archivos quedan en C:\sync; si el ultimo fue el 0001 seran 0002 y 0003)
EXEC SP_GUARDAR_CLIENTE(3, 1, 'CEDULA', '606660666', 'Jorge Castro Perez V3');

EXEC SP_GENERAR_PAQUETE('SUC03', 'CENTRAL', FN_SIGUIENTE_PAQUETE('CENTRAL'));

SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 3 AND idClienteLocal = 1;

-- c) EN CENTRAL: aplicar primero el lote nuevo y despues el viejo
--    EXEC SP_PROCESAR_PAQUETE('lote_SUC03_0003.txt', 'SUC03', 'CENTRAL');
--    EXEC SP_PROCESAR_PAQUETE('lote_SUC03_0002.txt', 'SUC03', 'CENTRAL');
-- d) EN CENTRAL: el cliente queda con la version 3; el lote viejo sale OMITIDO o DESCARTADO en la bitacora
--    SELECT nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 3 AND idClienteLocal = 1;
--    SELECT contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, resultadoBitacora FROM BITACORA_SYNC ORDER BY idBitacora DESC;
