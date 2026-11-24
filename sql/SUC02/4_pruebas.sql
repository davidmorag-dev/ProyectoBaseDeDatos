-- SUC02. Pruebas de comportamiento. Se ejecuta despues de 3_operar.sql.
-- Un bloque a la vez (F9, y los EXEC con F5). Los pasos de la central estan en CENTRAL/4_pruebas.sql.
SET SERVEROUTPUT ON

------------------------------------------------------------
-- PRUEBA 1. FACTURAR CON LA CENTRAL DETENIDA
------------------------------------------------------------
-- facturas antes
SELECT COUNT(*) AS facturas FROM FACTURA;

VARIABLE idFactura NUMBER
EXEC SP_EMITIR_FACTURA(2, 2, 1, '2:1;5:3', :idFactura);
PRINT idFactura

-- la factura queda local y su envio PENDIENTE
SELECT idFactura, totalFactura FROM FACTURA ORDER BY idFactura DESC FETCH FIRST 2 ROWS ONLY;
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

------------------------------------------------------------
-- PRUEBA 2. BLOQUE AGOTADO: se pide uno nuevo y se recibe de la central
------------------------------------------------------------
-- a) se deja el bloque casi consumido (quedan dos numeros)
UPDATE RANGO_FACTURA SET proximoNumeroRango = numeroFinalRango - 1 WHERE idSucursal = 2 AND estadoRango = 'ACTIVO';
COMMIT;

-- b) dos facturas usan los dos ultimos numeros. Al pasar el 80% se pide un bloque nuevo
EXEC SP_EMITIR_FACTURA(2, 2, 1, '1:1', :idFactura);
EXEC SP_EMITIR_FACTURA(2, 2, 1, '1:1', :idFactura);

-- c) el bloque quedo AGOTADO y hay una solicitud PENDIENTE hacia la central
SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA;
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA WHERE tablaOrigenSalida = 'RANGO_FACTURA' GROUP BY tablaOrigenSalida, estadoSalida;

-- d) una tercera factura falla porque no hay numeros (-20010) y no queda nada a medias
EXEC SP_EMITIR_FACTURA(2, 2, 1, '1:1', :idFactura);

-- e) en la central: CENTRAL/4_pruebas.sql, prueba 6 (ciclo y bloque nuevo)

-- f) ahora hay un bloque nuevo ACTIVO y la factura si se puede emitir
SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA ORDER BY idRango;
EXEC SP_EMITIR_FACTURA(2, 2, 1, '1:1', :idFactura);
PRINT idFactura

------------------------------------------------------------
-- PRUEBA 3. REGISTROS RECHAZADOS: no queda una factura a medias
------------------------------------------------------------
SELECT COUNT(*) AS facturas FROM FACTURA;
-- cantidad cero (ORA-02290)
EXEC SP_EMITIR_FACTURA(2, 2, 1, '1:0', :idFactura);
-- producto que no existe (ORA-01403)
EXEC SP_EMITIR_FACTURA(2, 2, 1, '99:1', :idFactura);
-- borrar un cliente que ya tiene facturas (ORA-02292)
DELETE FROM CLIENTE WHERE idSucursalOrigen = 2 AND idClienteLocal = 1;
-- los conteos no cambiaron
SELECT COUNT(*) AS facturas FROM FACTURA;

------------------------------------------------------------
-- PRUEBA 4. MODIFICAR UN CLIENTE: sube la version y viaja a todas las sucursales
------------------------------------------------------------
EXEC SP_GUARDAR_CLIENTE(2, 2, 'CEDULA', '404440444', 'Cliente Modificado SUC02');
SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 2 ORDER BY idClienteLocal;
-- despues del ciclo de la central, en la otra sucursal y en la central se ve el nombre nuevo con la version 2
-- todos los clientes que tiene esta sucursal (propios y recibidos) con su origen; las dos Marias salen juntas
SELECT s.codigoSucursal AS origen, c.idClienteLocal, c.numeroIdentificacionCliente AS cedula, c.nombreCliente, c.versionCliente
FROM CLIENTE c JOIN SUCURSAL s ON s.idSucursal = c.idSucursalOrigen
ORDER BY c.nombreCliente, s.codigoSucursal;

------------------------------------------------------------
-- PRUEBA 5. RECUPERAR LA NUMERACION TRAS RESTAURAR UNA COPIA VIEJA
------------------------------------------------------------
-- el bloque activo se retira y se pide uno nuevo, asi nunca se repiten numeros
EXEC SP_RETIRAR_BLOQUE(2);
SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA ORDER BY idRango;
-- despues del ciclo de la central llega el bloque nuevo

------------------------------------------------------------
-- PRUEBA 6. ENVIO REPETIDO: un envio ya aplicado vuelve a viajar y la central no lo duplica
------------------------------------------------------------
-- a) EN CENTRAL: conteos antes (CENTRAL/4_pruebas.sql, prueba 1, el primer SELECT)
-- b) aqui: la primera factura ya APLICADA se vuelve a poner PENDIENTE
UPDATE SYNC_SALIDA SET estadoSalida = 'PENDIENTE'
WHERE idSalida = (SELECT MIN(idSalida) FROM SYNC_SALIDA WHERE tablaOrigenSalida = 'FACTURA');
COMMIT;

SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

-- c) EN CENTRAL: ciclo de esta sucursal; los conteos no cambian y la bitacora marca OMITIDO
--    EXEC SP_CICLO_SYNC('SUC02');
--    SELECT contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, resultadoBitacora FROM BITACORA_SYNC ORDER BY idBitacora DESC;
-- d) aqui: el envio vuelve a quedar APLICADO
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

------------------------------------------------------------
-- PRUEBA 7. CONFLICTO DE CATALOGO: gana el cambio mas reciente (va con CENTRAL/4_pruebas.sql, prueba 4)
------------------------------------------------------------
-- a) EN CENTRAL: EXEC SP_CAMBIAR_PRECIO(2, 390000);
-- b) aqui, antes del ciclo: se cambia el mismo producto con una fecha un minuto despues
UPDATE PRODUCTO SET precioActualProducto = 400000,
    fechaModificacionProducto = TO_DATE('24/11/2026 15:30:00', 'DD/MM/YYYY HH24:MI:SS')
WHERE idProducto = 2;
COMMIT;

SELECT idProducto, precioActualProducto, fechaModificacionProducto FROM PRODUCTO WHERE idProducto = 2;

-- c) EN CENTRAL: ciclo de esta sucursal (prueba 4, pasos c y d)
-- d) aqui: el precio sigue en 410000 porque su fecha es mas reciente; el cambio de la central llego DESCARTADO
SELECT idProducto, precioActualProducto, fechaModificacionProducto FROM PRODUCTO WHERE idProducto = 2;

SELECT origenRecibido, idEnvioRecibido, resultadoRecibido FROM SYNC_RECIBIDO WHERE origenRecibido = 'CENTRAL' ORDER BY idEnvioRecibido DESC;

-- e) EN CENTRAL: pasado el minuto, la central vuelve a fijar el precio (prueba 4, paso e). Aqui ya debe salir 390000
SELECT idProducto, precioActualProducto, fechaModificacionProducto FROM PRODUCTO WHERE idProducto = 2;
