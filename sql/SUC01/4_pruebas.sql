-- SUC01. Pruebas de comportamiento. Se ejecuta despues de 3_operar.sql.
-- Un bloque a la vez (F9, y los EXEC con F5). Los pasos de la central estan en CENTRAL/4_pruebas.sql.
SET SERVEROUTPUT ON

------------------------------------------------------------
-- PRUEBA 1. FACTURAR CON LA CENTRAL DETENIDA
------------------------------------------------------------
-- facturas antes
SELECT COUNT(*) AS facturas FROM FACTURA;

VARIABLE idFactura NUMBER
EXEC SP_EMITIR_FACTURA(1, 1, 1, '2:1;5:3', :idFactura);
PRINT idFactura

-- la factura queda local y su envio PENDIENTE
SELECT idFactura, totalFactura FROM FACTURA ORDER BY idFactura DESC FETCH FIRST 2 ROWS ONLY;
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

------------------------------------------------------------
-- PRUEBA 2. BLOQUE AGOTADO: se pide uno nuevo y se recibe de la central
------------------------------------------------------------
-- a) se deja el bloque casi consumido (quedan dos numeros)
UPDATE RANGO_FACTURA SET proximoNumeroRango = numeroFinalRango - 1 WHERE idSucursal = 1 AND estadoRango = 'ACTIVO';
COMMIT;

-- b) dos facturas usan los dos ultimos numeros. Al pasar el 80% se pide un bloque nuevo
EXEC SP_EMITIR_FACTURA(1, 1, 1, '1:1', :idFactura);
EXEC SP_EMITIR_FACTURA(1, 1, 1, '1:1', :idFactura);

-- c) el bloque quedo AGOTADO y hay una solicitud PENDIENTE hacia la central
SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA;
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA WHERE tablaOrigenSalida = 'RANGO_FACTURA' GROUP BY tablaOrigenSalida, estadoSalida;

-- d) una tercera factura falla porque no hay numeros (-20010) y no queda nada a medias
EXEC SP_EMITIR_FACTURA(1, 1, 1, '1:1', :idFactura);

-- e) en la central: CENTRAL/4_pruebas.sql, prueba 6 (ciclo y bloque nuevo)

-- f) ahora hay un bloque nuevo ACTIVO y la factura si se puede emitir
SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA ORDER BY idRango;
EXEC SP_EMITIR_FACTURA(1, 1, 1, '1:1', :idFactura);
PRINT idFactura

------------------------------------------------------------
-- PRUEBA 3. REGISTROS RECHAZADOS: no queda una factura a medias
------------------------------------------------------------
SELECT COUNT(*) AS facturas FROM FACTURA;
-- cantidad cero (ORA-02290)
EXEC SP_EMITIR_FACTURA(1, 1, 1, '1:0', :idFactura);
-- producto que no existe (ORA-01403)
EXEC SP_EMITIR_FACTURA(1, 1, 1, '99:1', :idFactura);
-- borrar un cliente que ya tiene facturas (ORA-02292)
DELETE FROM CLIENTE WHERE idSucursalOrigen = 1 AND idClienteLocal = 1;
-- los conteos no cambiaron
SELECT COUNT(*) AS facturas FROM FACTURA;

------------------------------------------------------------
-- PRUEBA 4. MODIFICAR UN CLIENTE: sube la version y viaja a todas las sucursales
------------------------------------------------------------
EXEC SP_GUARDAR_CLIENTE(1, 2, 'CEDULA', '202220222', 'Cliente Modificado SUC01');
SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 1 ORDER BY idClienteLocal;
-- despues del ciclo de la central, en la otra sucursal y en la central se ve el nombre nuevo con la version 2

------------------------------------------------------------
-- PRUEBA 5. RECUPERAR LA NUMERACION TRAS RESTAURAR UNA COPIA VIEJA
------------------------------------------------------------
-- el bloque activo se retira y se pide uno nuevo, asi nunca se repiten numeros
EXEC SP_RETIRAR_BLOQUE(1);
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
--    EXEC SP_CICLO_SYNC('SUC01');
--    SELECT contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, resultadoBitacora FROM BITACORA_SYNC ORDER BY idBitacora DESC;
-- d) aqui: el envio vuelve a quedar APLICADO
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;
