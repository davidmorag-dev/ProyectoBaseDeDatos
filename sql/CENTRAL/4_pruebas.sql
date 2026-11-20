-- CENTRAL. Pruebas de comportamiento del modo conectado. Se ejecuta despues de 3_operar.sql.
-- Un bloque a la vez (F9, y los EXEC con F5). Algunos pasos se hacen en una sucursal; el comentario lo dice.
SET SERVEROUTPUT ON

------------------------------------------------------------
-- 0. DETENER LA SINCRONIZACION AUTOMATICA (para que no se meta en medio de las pruebas)
------------------------------------------------------------
EXEC DBMS_SCHEDULER.DISABLE('JOB_SYNC_SUC01');
EXEC DBMS_SCHEDULER.DISABLE('JOB_SYNC_SUC02');

------------------------------------------------------------
-- PRUEBA 1. REPETIR EL CICLO: no se duplica nada
------------------------------------------------------------
-- conteos antes
SELECT (SELECT COUNT(*) FROM CLIENTE) AS clientes, (SELECT COUNT(*) FROM FACTURA) AS facturas,
    (SELECT COUNT(*) FROM SYNC_RECIBIDO) AS recibidos, (SELECT COUNT(*) FROM BITACORA_SYNC) AS bitacora FROM DUAL;

EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');

-- conteos despues (deben ser iguales a los de antes)
SELECT (SELECT COUNT(*) FROM CLIENTE) AS clientes, (SELECT COUNT(*) FROM FACTURA) AS facturas,
    (SELECT COUNT(*) FROM SYNC_RECIBIDO) AS recibidos, (SELECT COUNT(*) FROM BITACORA_SYNC) AS bitacora FROM DUAL;

------------------------------------------------------------
-- PRUEBA 2. NODO CAIDO: una sucursal no responde y la otra sigue
------------------------------------------------------------
-- a) En la computadora de SUC02, en PowerShell como administrador:  lsnrctl stop
-- b) Aqui, el ciclo de SUC02 no puede conectar: termina sin romper y lo anota
EXEC SP_CICLO_SYNC('SUC02');

-- c) SUC02 debe estar SIN_CONEXION y la bitacora debe tener una fila ERROR
-- el enlace no responde: debe dar ORA-12170 (timeout) u otro error de red
SELECT 1 FROM DUAL@LNK_SUC02;

SELECT codigoSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal FROM SUCURSAL;
SELECT contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, resultadoBitacora FROM BITACORA_SYNC
WHERE resultadoBitacora = 'ERROR' ORDER BY idBitacora DESC;

-- d) SUC01 si sincroniza (debe quedar CONECTADA)
EXEC SP_CICLO_SYNC('SUC01');
SELECT codigoSucursal, estadoConexionSucursal FROM SUCURSAL;

-- e) En SUC02, en PowerShell:  lsnrctl start   (esperar 1 minuto). Despues, la central se recupera sola
EXEC SP_CICLO_SYNC('SUC02');
SELECT codigoSucursal, estadoConexionSucursal FROM SUCURSAL;

------------------------------------------------------------
-- PRUEBA 3. CENTRAL DETENIDA: las sucursales siguen facturando
------------------------------------------------------------
-- a) Detener la central (PowerShell como administrador):  Stop-Service OracleServiceXE -Force
-- b) Cada sucursal factura con normalidad (4_pruebas.sql de la sucursal, prueba 1). Sus envios quedan PENDIENTE
-- c) Volver a levantar la central:  Start-Service OracleServiceXE   (esperar 1 minuto)
-- d) Ejecutar el ciclo de cada sucursal: lo acumulado se aplica
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');
SELECT idFactura, idSucursalEmisora, totalFactura FROM FACTURA ORDER BY idFactura;

------------------------------------------------------------
-- PRUEBA 4. CONFLICTO DE CATALOGO: gana el cambio mas reciente
------------------------------------------------------------
-- a) La central cambia el precio del producto 2
EXEC SP_CAMBIAR_PRECIO(2, 390000);

-- b) En SUC01, antes del ciclo, se modifica el mismo producto con una fecha posterior:
--    UPDATE PRODUCTO SET precioActualProducto = 400000, fechaModificacionProducto = SYSDATE + 1/1440 WHERE idProducto = 2;
--    COMMIT;

-- c) Ciclo de las dos sucursales
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');

-- d) SUC01 descarta el cambio de la central (DESCARTADO) y conserva 400000. SUC02 si lo recibe (390000)
SELECT p.idProducto, p.precioActualProducto AS central, s1.precioActualProducto AS suc01, s2.precioActualProducto AS suc02
FROM PRODUCTO p
JOIN PRODUCTO@LNK_SUC01 s1 ON s1.idProducto = p.idProducto
JOIN PRODUCTO@LNK_SUC02 s2 ON s2.idProducto = p.idProducto
WHERE p.idProducto = 2;
SELECT contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, resultadoBitacora FROM BITACORA_SYNC
WHERE tablaAfectadaBitacora = 'PRODUCTO' ORDER BY idBitacora DESC;

------------------------------------------------------------
-- PRUEBA 5. REGISTROS RECHAZADOS: Oracle no deja datos a medias
------------------------------------------------------------
-- precio negativo (ORA-02290)
EXEC SP_CAMBIAR_PRECIO(1, -5);
-- producto que no existe (-20002)
EXEC SP_CAMBIAR_PRECIO(99, 100);
-- borrar un cliente que ya tiene facturas (ORA-02292)
DELETE FROM CLIENTE WHERE idSucursalOrigen = 1 AND idClienteLocal = 1;
-- nada cambio: el precio del producto 1 sigue igual y el cliente sigue existiendo
SELECT idProducto, precioActualProducto FROM PRODUCTO WHERE idProducto = 1;
SELECT COUNT(*) AS clientes FROM CLIENTE;

------------------------------------------------------------
-- PRUEBA 6. BLOQUE AGOTADO: la central entrega un bloque nuevo
------------------------------------------------------------
-- La sucursal agota su bloque y pide otro (4_pruebas.sql de la sucursal, prueba 2). Aqui se ve la solicitud
EXEC SP_CICLO_SYNC('SUC01');
SELECT idRango, idSucursal, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA ORDER BY idRango;

------------------------------------------------------------
-- PRUEBA 7. CAMBIOS FUERA DE ORDEN (SUC03): la version mas nueva se conserva aunque el lote viejo llegue despues
------------------------------------------------------------
-- SUC03 genera dos lotes con el mismo cliente (SUC03/4_pruebas.sql, prueba 7). Cambiar los numeros por los que lleguen a C:\sync
-- a) primero el lote mas nuevo (numero mas alto) y despues el viejo
EXEC SP_PROCESAR_PAQUETE('lote_SUC03_0005.txt', 'SUC03', 'CENTRAL');

EXEC SP_PROCESAR_PAQUETE('lote_SUC03_0004.txt', 'SUC03', 'CENTRAL');

-- b) el cliente queda con la version 3 y el lote viejo sale OMITIDO o DESCARTADO
SELECT nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 3 AND idClienteLocal = 1;

SELECT contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, resultadoBitacora FROM BITACORA_SYNC ORDER BY idBitacora DESC;

------------------------------------------------------------
-- 7. VOLVER A ACTIVAR LA SINCRONIZACION AUTOMATICA
------------------------------------------------------------
EXEC DBMS_SCHEDULER.ENABLE('JOB_SYNC_SUC01');
EXEC DBMS_SCHEDULER.ENABLE('JOB_SYNC_SUC02');
