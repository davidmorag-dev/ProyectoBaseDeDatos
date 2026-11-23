-- VERIFICACIONES. Un bloque por cada indicador de la rubrica de la demostracion.
-- Cada paso dice en que nodo se corre: [CENTRAL], [SUC01], [SUC02], [SUC03] o [SYSTEM].
-- Antes de cada paso, cambiar la conexion arriba a la derecha. Un bloque a la vez (F9, y los EXEC con F5).
-- Se asume una instalacion limpia: 0_borrarTodo.sql, 1_instalar, 1_motor, 2_sucursal / 2_conectado y 4_enlaces.
-- Al final (RESUMEN) una consulta en la central dice SI o NO para cada indicador.
SET SERVEROUTPUT ON

------------------------------------------------------------
-- 0. PREPARACION
------------------------------------------------------------
-- [CENTRAL] si existen los trabajos automaticos, apagarlos para que el ciclo solo corra a mano
--           (si no existen da error; no importa)
EXEC DBMS_SCHEDULER.DISABLE('JOB_SYNC_SUC01');
EXEC DBMS_SCHEDULER.DISABLE('JOB_SYNC_SUC02');


------------------------------------------------------------
-- INDICADOR 1. LAS INSTANCIAS OPERAN DE FORMA AUTONOMA
-- Cada nodo tiene sus propias tablas, procedimientos, catalogo y bloque de numeracion
------------------------------------------------------------
-- [CENTRAL] [SUC01] [SUC02] objetos con errores (no debe devolver filas)
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

-- [SUC01] [SUC02] datos propios: catalogo, clientes y su bloque de facturas (SUC01 1-1000, SUC02 1001-2000)
SELECT 'PRODUCTO' AS tabla, COUNT(*) AS filas FROM PRODUCTO
UNION ALL SELECT 'CLIENTE', COUNT(*) FROM CLIENTE
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA;
SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA;

-- [CENTRAL] la central reparte los bloques y solo ella tiene enlaces (deben salir LNK_SUC01 y LNK_SUC02)
SELECT idRango, idSucursal, numeroInicialRango, numeroFinalRango, estadoRango FROM RANGO_FACTURA ORDER BY idRango;
SELECT db_link, username, host FROM user_db_links;

-- [SUC01] [SUC02] las sucursales no tienen enlaces (no debe devolver filas)
SELECT db_link FROM user_db_links;


------------------------------------------------------------
-- INDICADOR 2. LAS SUCURSALES FACTURAN CON LA CENTRAL DETENIDA
------------------------------------------------------------
-- a) Detener la central
--    Dia de la demo, en la computadora de la central (PowerShell como administrador):  Stop-Service OracleServiceXE -Force
--    Practica en una sola computadora: no se puede apagar la central sin apagar todo; basta con no correr el ciclo.
--    SP_EMITIR_FACTURA no usa ningun enlace, asi que la central no participa.

-- b) [SUC01] antes: cuantas facturas hay
SELECT COUNT(*) AS facturas FROM FACTURA;

-- c) [SUC01] facturar (cliente 1 = Maria, cliente 2 = Carlos)
VARIABLE idFactura NUMBER
EXEC SP_EMITIR_FACTURA(1, 1, 1, '1:1;5:2', :idFactura);
PRINT idFactura
EXEC SP_EMITIR_FACTURA(1, 1, 2, '3:1;4:1', :idFactura);
PRINT idFactura

-- d) [SUC02] lo mismo en la otra sucursal (sus numeros empiezan en 1001)
VARIABLE idFactura NUMBER
EXEC SP_EMITIR_FACTURA(2, 2, 1, '2:1;7:2', :idFactura);
PRINT idFactura
EXEC SP_EMITIR_FACTURA(2, 2, 2, '6:1', :idFactura);
PRINT idFactura

-- e) [SUC01] [SUC02] despues: las facturas quedan locales y su envio PENDIENTE hacia la central
SELECT idFactura, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

-- f) Volver a levantar la central (dia de la demo):  Start-Service OracleServiceXE   (esperar 1 minuto)


------------------------------------------------------------
-- INDICADOR 3. SINCRONIZACION EN MODO CONECTADO, EN VIVO
------------------------------------------------------------
-- a) [CENTRAL] antes: lo que tiene pendiente cada sucursal y lo que tiene la central
SELECT 'SUC01' AS nodo, tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA@LNK_SUC01 GROUP BY tablaOrigenSalida, estadoSalida
UNION ALL
SELECT 'SUC02', tablaOrigenSalida, estadoSalida, COUNT(*) FROM SYNC_SALIDA@LNK_SUC02 GROUP BY tablaOrigenSalida, estadoSalida;
SELECT (SELECT COUNT(*) FROM CLIENTE) AS clientes, (SELECT COUNT(*) FROM FACTURA) AS facturas FROM DUAL;

-- b) [CENTRAL] ciclo: cada uno primero sube lo de la sucursal y despues le baja lo de la central
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');
EXEC SP_CICLO_SYNC('SUC01');

-- c) [CENTRAL] despues: todo APLICADO, la central con los clientes y facturas, y la bitacora sin ERROR
SELECT 'SUC01' AS nodo, tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA@LNK_SUC01 GROUP BY tablaOrigenSalida, estadoSalida
UNION ALL
SELECT 'SUC02', tablaOrigenSalida, estadoSalida, COUNT(*) FROM SYNC_SALIDA@LNK_SUC02 GROUP BY tablaOrigenSalida, estadoSalida;
SELECT (SELECT COUNT(*) FROM CLIENTE) AS clientes, (SELECT COUNT(*) FROM FACTURA) AS facturas FROM DUAL;
SELECT contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, resultadoBitacora FROM BITACORA_SYNC ORDER BY idBitacora DESC;

-- d) [CENTRAL] cambio de precio: la central lo cambia y baja a las dos sucursales
EXEC SP_CAMBIAR_PRECIO(1, 455000);
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');
SELECT p.idProducto, p.precioActualProducto AS central, s1.precioActualProducto AS suc01, s2.precioActualProducto AS suc02
FROM PRODUCTO p
JOIN PRODUCTO@LNK_SUC01 s1 ON s1.idProducto = p.idProducto
JOIN PRODUCTO@LNK_SUC02 s2 ON s2.idProducto = p.idProducto
ORDER BY p.idProducto;

-- e) [CENTRAL] repetir el ciclo no duplica nada (los conteos deben quedar iguales)
SELECT (SELECT COUNT(*) FROM CLIENTE) AS clientes, (SELECT COUNT(*) FROM FACTURA) AS facturas FROM DUAL;
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');
SELECT (SELECT COUNT(*) FROM CLIENTE) AS clientes, (SELECT COUNT(*) FROM FACTURA) AS facturas FROM DUAL;


------------------------------------------------------------
-- INDICADOR 4. SINCRONIZACION EN MODO DIFERIDO (SUC03, POR CORREO), EN VIVO
-- Requiere SUC03 instalada con 3_correo.sql y CENTRAL con 3_correo.sql
------------------------------------------------------------
-- a) [SUC03] facturar sin red: queda PENDIENTE
VARIABLE idFactura NUMBER
EXEC SP_EMITIR_FACTURA(3, 3, 1, '7:1;8:2', :idFactura);
PRINT idFactura
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

-- b) [SUC03] generar el lote (queda en C:\sync): los envios pasan a ENVIADO
EXEC SP_GENERAR_PAQUETE('SUC03', 'CENTRAL', FN_SIGUIENTE_PAQUETE('CENTRAL'));
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

-- c) Pasar el archivo por correo a C:\sync de la central

-- d) [CENTRAL] antes y despues de aplicar el lote (cambiar el numero por el del archivo que llego)
SELECT COUNT(*) AS facturasSuc03 FROM FACTURA WHERE idSucursalEmisora = 3;
EXEC SP_PROCESAR_PAQUETE('lote_SUC03_0001.txt', 'SUC03', 'CENTRAL');
SELECT COUNT(*) AS facturasSuc03 FROM FACTURA WHERE idSucursalEmisora = 3;

-- e) [CENTRAL] el mismo lote otra vez: no se duplica (OMITIDO)
EXEC SP_PROCESAR_PAQUETE('lote_SUC03_0001.txt', 'SUC03', 'CENTRAL');
SELECT COUNT(*) AS facturasSuc03 FROM FACTURA WHERE idSucursalEmisora = 3;

-- f) [CENTRAL] generar la respuesta para SUC03 y pasarla por correo
EXEC SP_GENERAR_PAQUETE('CENTRAL', 'SUC03', FN_SIGUIENTE_PAQUETE('SUC03'));

-- g) [SUC03] aplicar la respuesta: los envios pasan a APLICADO y llegan precios y clientes
EXEC SP_PROCESAR_PAQUETE('respuesta_SUC03_0001.txt', 'CENTRAL', 'SUC03');
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;
SELECT idSucursalOrigen, COUNT(*) AS clientes FROM CLIENTE GROUP BY idSucursalOrigen;


------------------------------------------------------------
-- INDICADOR 5. NODO CAIDO: UNA SUCURSAL NO RESPONDE Y LA OTRA SIGUE
------------------------------------------------------------
-- a) Tirar SUC02
--    Dia de la demo, en la computadora de SUC02 (PowerShell como administrador):  lsnrctl stop
--    Practica en una sola computadora (lsnrctl stop tumbaria todo): bloquear el usuario de SUC02
--      [SYSTEM]  ALTER USER &usuarioSuc02 ACCOUNT LOCK;
--      [CENTRAL] cerrar la conexion que el enlace ya tenia abierta:
COMMIT;
ALTER SESSION CLOSE DATABASE LINK LNK_SUC02;

-- b) [CENTRAL] el enlace ya no responde (ORA-12541, ORA-12170 o ORA-28000 en la practica)
SELECT 1 FROM DUAL@LNK_SUC02;

-- c) [CENTRAL] el ciclo de SUC02 no se cae: la marca SIN_CONEXION y anota ERROR en la bitacora
EXEC SP_CICLO_SYNC('SUC02');
SELECT codigoSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal FROM SUCURSAL;
SELECT contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, resultadoBitacora FROM BITACORA_SYNC
WHERE resultadoBitacora = 'ERROR' ORDER BY idBitacora DESC;

-- d) [CENTRAL] SUC01 sigue sincronizando normal
EXEC SP_CICLO_SYNC('SUC01');
SELECT codigoSucursal, estadoConexionSucursal FROM SUCURSAL;

-- e) Levantar SUC02
--    Dia de la demo:  lsnrctl start   (esperar 1 minuto)
--    Practica:  [SYSTEM]  ALTER USER &usuarioSuc02 ACCOUNT UNLOCK;
-- f) [CENTRAL] se recupera solo con el siguiente ciclo (vuelve a CONECTADA)
EXEC SP_CICLO_SYNC('SUC02');
SELECT codigoSucursal, estadoConexionSucursal FROM SUCURSAL;


------------------------------------------------------------
-- INDICADOR 6. CONFLICTO DE CATALOGO Y REGISTRO RECHAZADO
------------------------------------------------------------
-- CONFLICTO: gana el cambio mas reciente
-- a) [CENTRAL] la central cambia el precio del producto 2
EXEC SP_CAMBIAR_PRECIO(2, 390000);

-- b) [SUC01] antes del ciclo, se cambia el mismo producto con una fecha posterior
UPDATE PRODUCTO SET precioActualProducto = 400000, fechaModificacionProducto = SYSDATE + 1/1440 WHERE idProducto = 2;
COMMIT;

-- c) [CENTRAL] ciclo: SUC01 descarta el de la central (DESCARTADO) y conserva 400000; SUC02 recibe 390000
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');
SELECT p.idProducto, p.precioActualProducto AS central, s1.precioActualProducto AS suc01, s2.precioActualProducto AS suc02
FROM PRODUCTO p
JOIN PRODUCTO@LNK_SUC01 s1 ON s1.idProducto = p.idProducto
JOIN PRODUCTO@LNK_SUC02 s2 ON s2.idProducto = p.idProducto
WHERE p.idProducto = 2;
SELECT contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, resultadoBitacora FROM BITACORA_SYNC
WHERE tablaAfectadaBitacora = 'PRODUCTO' ORDER BY idBitacora DESC;

-- d) [CENTRAL] la central, duena del catalogo, vuelve a fijar el precio y los tres nodos quedan iguales
--    Antes: horaCentral debe ser mayor que fechaSuc01 (pasado el minuto del paso b); si no, esperar y volver a consultar
SELECT SYSDATE AS horaCentral, fechaModificacionProducto AS fechaSuc01 FROM PRODUCTO@LNK_SUC01 WHERE idProducto = 2;
EXEC SP_CAMBIAR_PRECIO(2, 390000);
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');
SELECT p.idProducto, p.precioActualProducto AS central, s1.precioActualProducto AS suc01, s2.precioActualProducto AS suc02
FROM PRODUCTO p
JOIN PRODUCTO@LNK_SUC01 s1 ON s1.idProducto = p.idProducto
JOIN PRODUCTO@LNK_SUC02 s2 ON s2.idProducto = p.idProducto
WHERE p.idProducto = 2;

-- RECHAZADOS: Oracle no deja datos a medias
-- e) [CENTRAL] antes
SELECT idProducto, precioActualProducto FROM PRODUCTO WHERE idProducto = 1;
SELECT COUNT(*) AS clientes FROM CLIENTE;
-- precio negativo (ORA-02290)
EXEC SP_CAMBIAR_PRECIO(1, -5);
-- producto que no existe (-20002)
EXEC SP_CAMBIAR_PRECIO(99, 100);
-- borrar un cliente que ya tiene facturas (ORA-02292)
DELETE FROM CLIENTE WHERE idSucursalOrigen = 1 AND idClienteLocal = 1;
-- despues: nada cambio
SELECT idProducto, precioActualProducto FROM PRODUCTO WHERE idProducto = 1;
SELECT COUNT(*) AS clientes FROM CLIENTE;

-- f) [SUC01] antes
SELECT COUNT(*) AS facturas FROM FACTURA;
VARIABLE idFactura NUMBER
-- cantidad cero (ORA-02290)
EXEC SP_EMITIR_FACTURA(1, 1, 1, '1:0', :idFactura);
-- producto que no existe (ORA-01403)
EXEC SP_EMITIR_FACTURA(1, 1, 1, '99:1', :idFactura);
-- despues: no quedo ninguna factura a medias
SELECT COUNT(*) AS facturas FROM FACTURA;


------------------------------------------------------------
-- INDICADOR 7. UNICIDAD DEL CONSECUTIVO CON LAS SUCURSALES AISLADAS
-- Cada sucursal factura solo con su bloque; los bloques nunca se cruzan
------------------------------------------------------------
-- a) [CENTRAL] los bloques no se traslapan (no debe devolver filas)
SELECT a.idRango, b.idRango FROM RANGO_FACTURA a JOIN RANGO_FACTURA b
ON a.idRango < b.idRango AND a.numeroInicialRango <= b.numeroFinalRango AND b.numeroInicialRango <= a.numeroFinalRango;

-- b) [CENTRAL] cada sucursal facturo dentro de su bloque (SUC01 1-1000, SUC02 1001-2000)
SELECT s.codigoSucursal, MIN(f.idFactura) AS primera, MAX(f.idFactura) AS ultima, COUNT(*) AS facturas
FROM FACTURA f JOIN SUCURSAL s ON s.idSucursal = f.idSucursalEmisora
GROUP BY s.codigoSucursal ORDER BY s.codigoSucursal;

-- c) [SUC01] bloque agotado: se dejan dos numeros, se consumen y se pide uno nuevo
UPDATE RANGO_FACTURA SET proximoNumeroRango = numeroFinalRango - 1 WHERE idSucursal = 1 AND estadoRango = 'ACTIVO';
COMMIT;
VARIABLE idFactura NUMBER
EXEC SP_EMITIR_FACTURA(1, 1, 1, '1:1', :idFactura);
EXEC SP_EMITIR_FACTURA(1, 1, 1, '1:1', :idFactura);
SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA;
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA WHERE tablaOrigenSalida = 'RANGO_FACTURA' GROUP BY tablaOrigenSalida, estadoSalida;
-- sin numeros la factura falla (-20010) y no queda nada a medias
EXEC SP_EMITIR_FACTURA(1, 1, 1, '1:1', :idFactura);

-- d) [CENTRAL] el ciclo entrega un bloque nuevo que no se cruza con ninguno
EXEC SP_CICLO_SYNC('SUC01');
SELECT idRango, idSucursal, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA ORDER BY idRango;

-- e) [SUC01] ya se puede facturar con el bloque nuevo
SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA ORDER BY idRango;
EXEC SP_EMITIR_FACTURA(1, 1, 1, '1:1', :idFactura);
PRINT idFactura


------------------------------------------------------------
-- INDICADOR 8. CLIENTES DUPLICADOS ENTRE SUCURSALES
-- Maria (cedula 101110111) esta en SUC01 (1,1) y en SUC02 (2,1)
------------------------------------------------------------
-- [SUC01] [SUC02] todos los clientes que tiene la sucursal (propios y recibidos), con su sucursal de origen.
--                 Antes del ciclo salen solo los propios; despues salen los de todas y las dos Marias juntas
SELECT s.codigoSucursal AS origen, c.idClienteLocal, c.numeroIdentificacionCliente AS cedula, c.nombreCliente, c.versionCliente
FROM CLIENTE c JOIN SUCURSAL s ON s.idSucursal = c.idSucursalOrigen
ORDER BY c.nombreCliente, s.codigoSucursal;

-- [CENTRAL] se guardan las dos (cada una tiene sus facturas)
SELECT idSucursalOrigen, idClienteLocal, numeroIdentificacionCliente, nombreCliente FROM CLIENTE
WHERE numeroIdentificacionCliente = '101110111';

-- [CENTRAL] la de SUC02 apunta a la de SUC01, que es la canonica
SELECT * FROM CLIENTE_EQUIVALENCIA;

-- [CENTRAL] cedulas repetidas en general
SELECT numeroIdentificacionCliente, COUNT(*) AS registros FROM CLIENTE
GROUP BY numeroIdentificacionCliente HAVING COUNT(*) > 1;


------------------------------------------------------------
-- INDICADOR 9. DISTRIBUCION DE LOS CLIENTES Y RETORNO CORRECTO AL NODO DE ORIGEN
------------------------------------------------------------
-- a) [SUC01] cliente nuevo (el caso del profe: se puede hacer con la central apagada; queda PENDIENTE)
EXEC SP_GUARDAR_CLIENTE(1, 8, 'CEDULA', '999990001', 'Cliente Profe');
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

-- b) [SUC02] antes: todavia no lo tiene (no debe devolver filas)
SELECT * FROM CLIENTE WHERE idSucursalOrigen = 1 AND idClienteLocal = 8;

-- c) [SUC01] modificar un cliente existente: sube a la version 2
EXEC SP_GUARDAR_CLIENTE(1, 2, 'CEDULA', '202220222', 'Cliente Modificado SUC01');
SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 1 ORDER BY idClienteLocal;

-- d) [CENTRAL] ciclo
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');

-- e) [SUC02] despues: ya lo tiene, y el modificado con la version 2
SELECT idSucursalOrigen, idClienteLocal, nombreCliente, versionCliente FROM CLIENTE
WHERE idSucursalOrigen = 1 AND idClienteLocal IN (2, 8);

-- f) [CENTRAL] los tres nodos tienen los mismos clientes con la misma version (no debe devolver filas)
SELECT NVL(NVL(c.idSucursalOrigen, s1.idSucursalOrigen), s2.idSucursalOrigen) AS suc,
       NVL(NVL(c.idClienteLocal, s1.idClienteLocal), s2.idClienteLocal) AS cliente,
       c.versionCliente AS central, s1.versionCliente AS suc01, s2.versionCliente AS suc02
FROM CLIENTE c
FULL JOIN CLIENTE@LNK_SUC01 s1 ON s1.idSucursalOrigen = c.idSucursalOrigen AND s1.idClienteLocal = c.idClienteLocal
FULL JOIN CLIENTE@LNK_SUC02 s2 ON s2.idSucursalOrigen = NVL(c.idSucursalOrigen, s1.idSucursalOrigen)
                              AND s2.idClienteLocal = NVL(c.idClienteLocal, s1.idClienteLocal)
WHERE c.idClienteLocal IS NULL OR s1.idClienteLocal IS NULL OR s2.idClienteLocal IS NULL
   OR c.versionCliente <> s1.versionCliente OR c.versionCliente <> s2.versionCliente;

-- g) [CENTRAL] retorno al origen: el cliente vuelve a SUC01 con la misma version y no la altera (DESCARTADO).
--    A SUC02 le llega como OK. SP_APLICAR_ENVIO solo aplica si la version es mayor
SELECT contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, resultadoBitacora FROM BITACORA_SYNC
WHERE tablaAfectadaBitacora = 'CLIENTE' ORDER BY idBitacora DESC FETCH FIRST 6 ROWS ONLY;


------------------------------------------------------------
-- INDICADOR 10. LA CENTRAL IDENTIFICA EL ORIGEN DE CADA VENTA
------------------------------------------------------------
-- [CENTRAL] cada factura con la sucursal que la emitio y la sucursal de su cliente
SELECT f.idFactura, s.codigoSucursal AS emitidaEn, f.idSucursalCliente, f.idClienteLocal, f.totalFactura
FROM FACTURA f JOIN SUCURSAL s ON s.idSucursal = f.idSucursalEmisora ORDER BY f.idFactura;

-- [CENTRAL] ventas por sucursal
SELECT s.codigoSucursal, COUNT(*) AS facturas, SUM(f.totalFactura) AS totalVendido
FROM FACTURA f JOIN SUCURSAL s ON s.idSucursal = f.idSucursalEmisora
GROUP BY s.codigoSucursal ORDER BY s.codigoSucursal;


------------------------------------------------------------
-- INDICADOR 11. EVIDENCIA DE LOS DATOS ANTES Y DESPUES EN CADA OPERACION
-- Cada indicador ya trae su consulta de antes y de despues. Esta es la pantalla de seguimiento completa
------------------------------------------------------------
-- [CENTRAL] lo que se movio con cada nodo, lo mas reciente primero
SELECT contraparteBitacora AS nodo, direccionBitacora AS direccion, tablaAfectadaBitacora AS tabla,
    resultadoBitacora AS resultado, TO_CHAR(fechaFinBitacora, 'YYYY-MM-DD HH24:MI:SS') AS fecha
FROM BITACORA_SYNC ORDER BY idBitacora DESC;

-- [CENTRAL] resumen por nodo, direccion y resultado
SELECT contraparteBitacora AS nodo, direccionBitacora AS direccion, resultadoBitacora AS resultado, COUNT(*) AS cantidad
FROM BITACORA_SYNC GROUP BY contraparteBitacora, direccionBitacora, resultadoBitacora ORDER BY 1, 2, 3;


------------------------------------------------------------
-- INDICADOR 12. CONCLUSIONES Y LIMITACIONES (se dicen de palabra)
------------------------------------------------------------
-- Conclusiones
--  * Cada sucursal factura sola, con su bloque de numeros; la central no es necesaria para vender.
--  * Nada se pierde: lo que no se pudo enviar queda PENDIENTE hasta el siguiente ciclo.
--  * Nada se duplica: SYNC_RECIBIDO marca OMITIDO lo que ya llego, y la version evita pisar algo nuevo con algo viejo.
--  * La central tiene la vista completa: sabe de que sucursal viene cada venta y detecta clientes repetidos.
-- Limitaciones
--  * Modelo en estrella: las sucursales no se hablan; un cliente de SUC01 llega a SUC02 solo cuando la central sincroniza.
--  * Mientras la central esta caida, las sucursales no reciben cambios de precio ni clientes de las otras.
--  * SUC03 (correo) tiene datos atrasados hasta que llega el lote; depende de que alguien pase el archivo.
--  * El conflicto de catalogo se resuelve por fecha (gana el mas reciente), sin revision humana.
--  * Los clientes repetidos se detectan por cedula pero no se fusionan solos.
--  * Si una sucursal agota su bloque estando aislada, no puede facturar hasta recibir uno nuevo.


------------------------------------------------------------
-- RESUMEN. [CENTRAL] SI o NO por indicador, segun lo que quedo en las tablas
------------------------------------------------------------
SELECT '1 Instancias autonomas' AS indicador,
       CASE WHEN (SELECT COUNT(*) FROM user_db_links WHERE db_link LIKE 'LNK_SUC0%') >= 2
             AND (SELECT COUNT(*) FROM user_objects WHERE status <> 'VALID') = 0 THEN 'SI' ELSE 'NO' END AS cumplido FROM DUAL
UNION ALL SELECT '2 Facturan sin la central',
       CASE WHEN (SELECT COUNT(DISTINCT idSucursalEmisora) FROM FACTURA) >= 2 THEN 'SI' ELSE 'NO' END FROM DUAL
UNION ALL SELECT '3 Sincronizacion conectada',
       CASE WHEN (SELECT COUNT(*) FROM BITACORA_SYNC WHERE contraparteBitacora IN ('SUC01', 'SUC02') AND resultadoBitacora = 'OK') > 0 THEN 'SI' ELSE 'NO' END FROM DUAL
UNION ALL SELECT '4 Sincronizacion diferida',
       CASE WHEN (SELECT COUNT(*) FROM SYNC_RECIBIDO WHERE origenRecibido = 'SUC03') > 0 THEN 'SI' ELSE 'NO' END FROM DUAL
UNION ALL SELECT '5 Nodo caido',
       CASE WHEN (SELECT COUNT(*) FROM BITACORA_SYNC WHERE tablaAfectadaBitacora = 'SUCURSAL' AND resultadoBitacora = 'ERROR') > 0 THEN 'SI' ELSE 'NO' END FROM DUAL
UNION ALL SELECT '6 Conflicto de catalogo',
       CASE WHEN (SELECT COUNT(*) FROM BITACORA_SYNC WHERE tablaAfectadaBitacora = 'PRODUCTO' AND resultadoBitacora = 'DESCARTADO') > 0 THEN 'SI' ELSE 'NO' END FROM DUAL
UNION ALL SELECT '7 Consecutivo unico (bloque nuevo entregado)',
       CASE WHEN (SELECT COUNT(*) FROM RANGO_FACTURA) > 3
             AND NOT EXISTS (SELECT 1 FROM RANGO_FACTURA a JOIN RANGO_FACTURA b ON a.idRango < b.idRango
                             AND a.numeroInicialRango <= b.numeroFinalRango AND b.numeroInicialRango <= a.numeroFinalRango) THEN 'SI' ELSE 'NO' END FROM DUAL
UNION ALL SELECT '8 Clientes duplicados',
       CASE WHEN (SELECT COUNT(*) FROM CLIENTE_EQUIVALENCIA) > 0 THEN 'SI' ELSE 'NO' END FROM DUAL
UNION ALL SELECT '9 Distribucion y retorno al origen',
       CASE WHEN (SELECT COUNT(*) FROM BITACORA_SYNC WHERE tablaAfectadaBitacora = 'CLIENTE' AND direccionBitacora = 'BAJADA' AND resultadoBitacora = 'OK') > 0
             AND (SELECT COUNT(*) FROM BITACORA_SYNC WHERE tablaAfectadaBitacora = 'CLIENTE' AND direccionBitacora = 'BAJADA' AND resultadoBitacora = 'DESCARTADO') > 0 THEN 'SI' ELSE 'NO' END FROM DUAL
UNION ALL SELECT '10 Origen de cada venta',
       CASE WHEN (SELECT COUNT(*) FROM FACTURA WHERE idSucursalEmisora IS NULL) = 0 AND (SELECT COUNT(*) FROM FACTURA) > 0 THEN 'SI' ELSE 'NO' END FROM DUAL
UNION ALL SELECT '11 Antes y despues (bitacora con movimientos)',
       CASE WHEN (SELECT COUNT(*) FROM BITACORA_SYNC) > 0 THEN 'SI' ELSE 'NO' END FROM DUAL;

-- [CENTRAL] al terminar, si se quieren los trabajos automaticos otra vez
-- EXEC DBMS_SCHEDULER.ENABLE('JOB_SYNC_SUC01');
-- EXEC DBMS_SCHEDULER.ENABLE('JOB_SYNC_SUC02');
