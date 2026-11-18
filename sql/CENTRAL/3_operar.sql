-- CENTRAL. Comprobar y operar. Se ejecuta cuantas veces haga falta.
-- Un bloque a la vez (F9; los BEGIN ... END y los EXEC con F5).

-- SECCION 1. COMPROBAR EL ESTADO DE LOS ENLACES (ONLINE u OFFLINE)

SET SERVEROUTPUT ON

-- 1. SUC01
DECLARE
    respuesta NUMBER;
BEGIN
    SELECT 1 INTO respuesta FROM DUAL@LNK_SUC01;
    DBMS_OUTPUT.PUT_LINE('SUC01: ONLINE');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('SUC01: OFFLINE (Oracle ' || SQLCODE || ')');
END;
/

-- 2. SUC02
DECLARE
    respuesta NUMBER;
BEGIN
    SELECT 1 INTO respuesta FROM DUAL@LNK_SUC02;
    DBMS_OUTPUT.PUT_LINE('SUC02: ONLINE');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('SUC02: OFFLINE (Oracle ' || SQLCODE || ')');
END;
/

-- 3. SUC03 (por correo, sin enlace)
PROMPT SUC03: CORREO (sin enlace directo)

-- SECCION 2. SUC01 Y SUC02 CONECTADAS

-- PARTE A. LA CENTRAL

-- A1. Confirmar el usuario y el servicio
SELECT USER AS usuario, SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS servicio,
       SYS_CONTEXT('USERENV', 'SERVER_HOST') AS equipo
FROM DUAL;

-- A2. Las 10 tablas del proyecto (debe devolver 10 filas)
SELECT table_name FROM user_tables
WHERE table_name IN ('SUCURSAL', 'PRODUCTO', 'CLIENTE', 'CLIENTE_EQUIVALENCIA', 'RANGO_FACTURA',
                     'FACTURA', 'DETALLE_FACTURA', 'SYNC_SALIDA', 'SYNC_RECIBIDO', 'BITACORA_SYNC')
ORDER BY table_name;

-- A3. Datos iniciales
SELECT 'SUCURSAL' AS tabla, COUNT(*) AS filas FROM SUCURSAL
UNION ALL SELECT 'PRODUCTO', COUNT(*) FROM PRODUCTO
UNION ALL SELECT 'RANGO_FACTURA', COUNT(*) FROM RANGO_FACTURA
UNION ALL SELECT 'CLIENTE', COUNT(*) FROM CLIENTE
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA;

-- A4. Procedimientos de la sincronizacion conectada (todos deben salir VALID)
SELECT object_name, object_type, status FROM user_objects
WHERE object_name IN ('SP_REGISTRAR_BITACORA', 'SP_CONSOLIDAR_CLIENTE', 'SP_ASIGNAR_BLOQUE',
                      'SP_APLICAR_SUBIDA', 'SP_APLICAR_BAJADA', 'SP_CICLO_SYNC',
                      'SP_CAMBIAR_PRECIO')
ORDER BY object_name;

-- A5. Objetos con errores (no debe devolver filas)
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

-- A6. Enlaces creados
SELECT db_link, username, host FROM user_db_links;

-- PARTE B. SUC01 (Ashly, Puntarenas)

-- B1. Probar el enlace (debe devolver 1)
SELECT 1 FROM DUAL@LNK_SUC01;

-- B2. Tablas de SUC01 vistas desde la central (debe devolver 10)
SELECT COUNT(*) AS tablasSuc01 FROM user_tables@LNK_SUC01;

-- B3. Datos de SUC01 vistos desde la central
SELECT 'CLIENTE' AS tabla, COUNT(*) AS filas FROM CLIENTE@LNK_SUC01
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA@LNK_SUC01
UNION ALL SELECT 'RANGO_FACTURA', COUNT(*) FROM RANGO_FACTURA@LNK_SUC01;

-- B4. Lo que SUC01 tiene pendiente de subir a la central
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA@LNK_SUC01
WHERE destinoSalida = 'CENTRAL' GROUP BY tablaOrigenSalida, estadoSalida;

-- B5. Ejecutar el ciclo de SUC01
EXEC SP_CICLO_SYNC('SUC01');

-- B6. Resultado del ciclo de SUC01
SELECT direccionBitacora, tablaAfectadaBitacora, fechaInicioBitacora, resultadoBitacora
FROM BITACORA_SYNC
WHERE contraparteBitacora = 'SUC01' ORDER BY idBitacora DESC FETCH FIRST 10 ROWS ONLY;

-- B7. Estado de SUC01 en la central
SELECT codigoSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal
FROM SUCURSAL
WHERE idSucursal = 1;

-- B8. Clientes y facturas de SUC01 que ya llegaron a la central
SELECT COUNT(*) AS clientesSuc01 FROM CLIENTE WHERE idSucursalOrigen = 1;
SELECT idFactura, idClienteLocal, fechaEmisionFactura, totalFactura
FROM FACTURA
WHERE idSucursalEmisora = 1
ORDER BY idFactura;

-- B9. Envios de la central hacia SUC01
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA
WHERE destinoSalida = 'SUC01' GROUP BY tablaOrigenSalida, estadoSalida;

-- B10. Trabajo automatico de SUC01
SELECT job_name, enabled, state, last_start_date, next_run_date
FROM user_scheduler_jobs
WHERE job_name = 'JOB_SYNC_SUC01';

-- PARTE C. SUC02 (Valeria, Alajuela)

-- C1. Probar el enlace (debe devolver 1)
SELECT 1 FROM DUAL@LNK_SUC02;

-- C2. Tablas de SUC02 vistas desde la central (debe devolver 10)
SELECT COUNT(*) AS tablasSuc02 FROM user_tables@LNK_SUC02;

-- C3. Datos de SUC02 vistos desde la central
SELECT 'CLIENTE' AS tabla, COUNT(*) AS filas FROM CLIENTE@LNK_SUC02
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA@LNK_SUC02
UNION ALL SELECT 'RANGO_FACTURA', COUNT(*) FROM RANGO_FACTURA@LNK_SUC02;

-- C4. Lo que SUC02 tiene pendiente de subir a la central
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA@LNK_SUC02
WHERE destinoSalida = 'CENTRAL' GROUP BY tablaOrigenSalida, estadoSalida;

-- C5. Ejecutar el ciclo de SUC02
EXEC SP_CICLO_SYNC('SUC02');

-- C6. Resultado del ciclo de SUC02 (nunca ERROR)
SELECT direccionBitacora, tablaAfectadaBitacora, fechaInicioBitacora, resultadoBitacora
FROM BITACORA_SYNC
WHERE contraparteBitacora = 'SUC02' ORDER BY idBitacora DESC FETCH FIRST 10 ROWS ONLY;

-- C7. Estado de SUC02 en la central
SELECT codigoSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal
FROM SUCURSAL
WHERE idSucursal = 2;

-- C8. Clientes y facturas de SUC02 que ya llegaron a la central
SELECT COUNT(*) AS clientesSuc02 FROM CLIENTE WHERE idSucursalOrigen = 2;
SELECT idFactura, idClienteLocal, fechaEmisionFactura, totalFactura
FROM FACTURA
WHERE idSucursalEmisora = 2
ORDER BY idFactura;

-- C9. Envios de la central hacia SUC02
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA
WHERE destinoSalida = 'SUC02' GROUP BY tablaOrigenSalida, estadoSalida;

-- C10. Trabajo automatico de SUC02
SELECT job_name, enabled, state, last_start_date, next_run_date
FROM user_scheduler_jobs
WHERE job_name = 'JOB_SYNC_SUC02';

-- PARTE D. SUC01 Y SUC02 JUNTAS

-- D1. Cliente repetido en las dos sucursales
SELECT * FROM CLIENTE_EQUIVALENCIA;

-- D2. Precios iguales en los tres nodos
SELECT central.idProducto, central.precioActualProducto AS central,
       suc01.precioActualProducto AS suc01, suc02.precioActualProducto AS suc02
FROM PRODUCTO central
JOIN PRODUCTO@LNK_SUC01 suc01 ON suc01.idProducto = central.idProducto
JOIN PRODUCTO@LNK_SUC02 suc02 ON suc02.idProducto = central.idProducto
ORDER BY central.idProducto;

-- D3. Bloques de facturas de cada sucursal
SELECT idSucursal, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango
FROM RANGO_FACTURA
WHERE idSucursal IN (1, 2) ORDER BY idSucursal, idRango;

-- SECCION 3. ACTIVAR LA SINCRONIZACION AUTOMATICA (cada 5 minutos)

BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name            => 'JOB_SYNC_SUC01',
        job_type            => 'STORED_PROCEDURE',
        job_action          => 'SP_CICLO_SYNC',
        number_of_arguments => 1,
        repeat_interval     => 'FREQ=MINUTELY;INTERVAL=5',
        enabled             => FALSE);
    DBMS_SCHEDULER.SET_JOB_ARGUMENT_VALUE('JOB_SYNC_SUC01', 1, 'SUC01');
    DBMS_SCHEDULER.ENABLE('JOB_SYNC_SUC01');
END;
/

BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name            => 'JOB_SYNC_SUC02',
        job_type            => 'STORED_PROCEDURE',
        job_action          => 'SP_CICLO_SYNC',
        number_of_arguments => 1,
        repeat_interval     => 'FREQ=MINUTELY;INTERVAL=5',
        enabled             => FALSE);
    DBMS_SCHEDULER.SET_JOB_ARGUMENT_VALUE('JOB_SYNC_SUC02', 1, 'SUC02');
    DBMS_SCHEDULER.ENABLE('JOB_SYNC_SUC02');
END;
/

-- EXEC DBMS_SCHEDULER.RUN_JOB('JOB_SYNC_SUC01');
-- EXEC DBMS_SCHEDULER.DISABLE('JOB_SYNC_SUC01');
-- SELECT job_name, enabled, last_start_date, next_run_date FROM USER_SCHEDULER_JOBS;

-- SECCION 4. SUC03 POR CORREO

-- PARTE E. LA CENTRAL LISTA PARA RECIBIR

-- E1. Confirmar el usuario y el servicio
SELECT USER AS usuario, SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS servicio FROM DUAL;

-- E2. SUC03 registrada en modo DIFERIDO
SELECT idSucursal, codigoSucursal, modoSyncSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal
FROM SUCURSAL
WHERE idSucursal = 3;

-- E3. Bloque de facturas de SUC03 (del 2001 al 3000)
SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango
FROM RANGO_FACTURA
WHERE idSucursal = 3;

-- E4. Procedimientos que usa el lote (todos deben salir VALID)
SELECT object_name, object_type, status FROM user_objects
WHERE object_name IN ('FN_CAMPO', 'FN_HUELLA', 'SP_PROCESAR_LOTE', 'SP_REGISTRAR_BITACORA',
                      'SP_CONSOLIDAR_CLIENTE', 'SP_ASIGNAR_BLOQUE')
ORDER BY object_name;

-- E5. Objetos con errores (no debe devolver filas)
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

-- PARTE F. LA CARPETA C:\sync

-- F1. Directorio de Oracle (debe devolver C:\sync)
SELECT directory_name, directory_path FROM all_directories WHERE directory_name = 'DIR_SYNC';

-- F2. Probar que Oracle puede escribir en C:\sync
DECLARE
    archivo UTL_FILE.FILE_TYPE;
BEGIN
    archivo := UTL_FILE.FOPEN('DIR_SYNC', 'prueba_central.txt', 'W');
    UTL_FILE.PUT_LINE(archivo, 'Prueba de CENTRAL ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
    UTL_FILE.FCLOSE(archivo);
    DBMS_OUTPUT.PUT_LINE('DIR_SYNC funciona');
END;
/

-- F3. Ver si el lote de Fiorella ya esta en C:\sync
DECLARE
    existe BOOLEAN;
    tamano NUMBER;
    bloque BINARY_INTEGER;
BEGIN
    UTL_FILE.FGETATTR('DIR_SYNC', 'lote_SUC03_0001.txt', existe, tamano, bloque);
    IF existe THEN
        DBMS_OUTPUT.PUT_LINE('Lote encontrado: ' || tamano || ' bytes');
    ELSE
        DBMS_OUTPUT.PUT_LINE('El lote no esta en C:\sync');
    END IF;
END;
/

-- PARTE G. APLICAR EL LOTE

-- G1. Conteos antes de aplicar
SELECT (SELECT COUNT(*) FROM CLIENTE WHERE idSucursalOrigen = 3) AS clientesSuc03,
       (SELECT COUNT(*) FROM FACTURA WHERE idSucursalEmisora = 3) AS facturasSuc03,
       (SELECT COUNT(*) FROM SYNC_RECIBIDO WHERE origenRecibido = 'SUC03') AS recibidosSuc03
FROM DUAL;

-- G2. Procesar el lote
EXEC SP_PROCESAR_LOTE('lote_SUC03_0001.txt', 'SUC03');

-- G3. Conteos despues de aplicar
SELECT (SELECT COUNT(*) FROM CLIENTE WHERE idSucursalOrigen = 3) AS clientesSuc03,
       (SELECT COUNT(*) FROM FACTURA WHERE idSucursalEmisora = 3) AS facturasSuc03,
       (SELECT COUNT(*) FROM SYNC_RECIBIDO WHERE origenRecibido = 'SUC03') AS recibidosSuc03
FROM DUAL;

-- G4. Envios de SUC03 recibidos y su resultado (APLICADO o DESCARTADO)
SELECT idEnvioRecibido, huellaRecibido, fechaRecepcionRecibido, resultadoRecibido FROM SYNC_RECIBIDO
WHERE origenRecibido = 'SUC03' ORDER BY idEnvioRecibido;

-- G5. Facturas de SUC03 en la central
SELECT idFactura, idClienteLocal, fechaEmisionFactura, totalFactura
FROM FACTURA
WHERE idSucursalEmisora = 3
ORDER BY idFactura;

-- G6. Detalle de esas facturas
SELECT d.idFactura, d.lineaDetalle, d.idProducto, d.cantidadDetalle, d.precioUnitarioDetalle
FROM DETALLE_FACTURA d JOIN FACTURA f ON f.idFactura = d.idFactura
WHERE f.idSucursalEmisora = 3 ORDER BY d.idFactura, d.lineaDetalle;

-- G7. Registro del lote aplicado (LOTE_APL debe salir OK)
SELECT direccionBitacora, tablaAfectadaBitacora, fechaInicioBitacora, resultadoBitacora
FROM BITACORA_SYNC
WHERE contraparteBitacora = 'SUC03' ORDER BY idBitacora DESC FETCH FIRST 10 ROWS ONLY;

-- PARTE H. REPETIR EL MISMO LOTE

-- H1. Procesar otra vez el mismo archivo
EXEC SP_PROCESAR_LOTE('lote_SUC03_0001.txt', 'SUC03');

-- H2. Conteos otra vez: iguales que en C3
SELECT (SELECT COUNT(*) FROM CLIENTE WHERE idSucursalOrigen = 3) AS clientesSuc03,
       (SELECT COUNT(*) FROM FACTURA WHERE idSucursalEmisora = 3) AS facturasSuc03,
       (SELECT COUNT(*) FROM SYNC_RECIBIDO WHERE origenRecibido = 'SUC03') AS recibidosSuc03
FROM DUAL;

-- PARTE I. LA RESPUESTA HACIA SUC03

-- I1. Procedimientos de la respuesta (todos deben salir VALID)
SELECT object_name, object_type, status FROM user_objects
WHERE object_name IN ('FN_SERIALIZAR', 'FN_SIGUIENTE_RESPUESTA', 'SP_GENERAR_RESPUESTA')
ORDER BY object_name;

-- I2. Trabajo que genera la respuesta a las 9 p. m.
SELECT job_name, enabled, state, next_run_date
FROM user_scheduler_jobs
WHERE job_name = 'JOB_RESPUESTA_SUC03';

-- I3. Lo que va en la respuesta
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA
WHERE destinoSalida = 'SUC03' GROUP BY tablaOrigenSalida, estadoSalida;

-- I4. Opcional: cambiar un precio
EXEC SP_CAMBIAR_PRECIO(1, 455000);

-- I5. Numero que tendra la proxima respuesta
SELECT FN_SIGUIENTE_RESPUESTA('SUC03') AS proximaRespuesta FROM DUAL;

-- I6. Generar la respuesta
EXEC SP_GENERAR_RESPUESTA('SUC03', FN_SIGUIENTE_RESPUESTA('SUC03'));

-- I7. Despues de generar: ENVIADO
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA
WHERE destinoSalida = 'SUC03' GROUP BY tablaOrigenSalida, estadoSalida;

-- I8. Con el siguiente lote de SUC03: APLICADO
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA
WHERE destinoSalida = 'SUC03' GROUP BY tablaOrigenSalida, estadoSalida;

-- SECCION 5. CONSULTAS PARA LA DEMOSTRACION

PROMPT Estado de las sucursales
SELECT codigoSucursal, modoSyncSucursal, estadoConexionSucursal,
       fechaUltimaSyncSucursal
FROM SUCURSAL ORDER BY idSucursal;

PROMPT Facturas recibidas por sucursal
SELECT idSucursalEmisora, COUNT(*) AS cantidadFacturas,
       SUM(totalFactura) AS totalVendido
FROM FACTURA GROUP BY idSucursalEmisora ORDER BY idSucursalEmisora;

PROMPT Ventas por sucursal en un periodo
-- :desde y :hasta son fechas
SELECT s.codigoSucursal AS sucursal, COUNT(*) AS facturas,
       SUM(f.totalFactura) AS totalVendido
FROM FACTURA f
JOIN SUCURSAL s ON s.idSucursal = f.idSucursalEmisora
WHERE f.fechaEmisionFactura >= :desde AND f.fechaEmisionFactura < :hasta
GROUP BY s.codigoSucursal
ORDER BY s.codigoSucursal;

PROMPT Envios centrales pendientes
SELECT destinoSalida, tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad
FROM SYNC_SALIDA
GROUP BY destinoSalida, tablaOrigenSalida, estadoSalida
ORDER BY destinoSalida, tablaOrigenSalida, estadoSalida;

PROMPT Recepciones y descartes en CENTRAL
SELECT origenRecibido, resultadoRecibido, COUNT(*) AS cantidad
FROM SYNC_RECIBIDO
GROUP BY origenRecibido, resultadoRecibido
ORDER BY origenRecibido, resultadoRecibido;

PROMPT Clientes duplicados detectados
SELECT idSucursalOrigen, idClienteLocal,
       idSucursalCanonica, idClienteCanonico
FROM CLIENTE_EQUIVALENCIA
ORDER BY idSucursalOrigen, idClienteLocal;

PROMPT Comparacion de precios entre CENTRAL, SUC01 y SUC02
SELECT central.idProducto, central.precioActualProducto AS precioCentral,
       suc01.precioActualProducto AS precioSuc01,
       suc02.precioActualProducto AS precioSuc02
FROM PRODUCTO central
JOIN PRODUCTO@LNK_SUC01 suc01 ON suc01.idProducto = central.idProducto
JOIN PRODUCTO@LNK_SUC02 suc02 ON suc02.idProducto = central.idProducto
ORDER BY central.idProducto;
