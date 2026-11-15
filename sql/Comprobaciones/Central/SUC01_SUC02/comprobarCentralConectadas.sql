-- Ejecutar solo en CENTRAL. Comprueba la central y su conexion directa con SUC01 (Ashly) y SUC02 (Valeria).
-- Cada bloque se corre por separado (seleccionar y F9) para ir comprobando.


-- PARTE A. LA CENTRAL

-- A1. Confirmar el usuario y el servicio (usuario CENTRAL, servicio XEPDB1)
SELECT USER AS usuario, SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS servicio, SYS_CONTEXT('USERENV', 'SERVER_HOST') AS equipo FROM DUAL;

-- A2. Las 10 tablas del proyecto (debe devolver 10 filas)
SELECT table_name FROM user_tables
WHERE table_name IN ('SUCURSAL', 'PRODUCTO', 'CLIENTE', 'CLIENTE_EQUIVALENCIA', 'RANGO_FACTURA',
                     'FACTURA', 'DETALLE_FACTURA', 'SYNC_SALIDA', 'SYNC_RECIBIDO', 'BITACORA_SYNC')
ORDER BY table_name;

-- A3. Datos iniciales (SUCURSAL 3, PRODUCTO 10, RANGO_FACTURA 3 o mas)
SELECT 'SUCURSAL' AS tabla, COUNT(*) AS filas FROM SUCURSAL
UNION ALL SELECT 'PRODUCTO', COUNT(*) FROM PRODUCTO
UNION ALL SELECT 'RANGO_FACTURA', COUNT(*) FROM RANGO_FACTURA
UNION ALL SELECT 'CLIENTE', COUNT(*) FROM CLIENTE
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA;

-- A4. Procedimientos de la sincronizacion conectada (todos deben salir VALID)
SELECT object_name, object_type, status FROM user_objects
WHERE object_name IN ('SP_REGISTRAR_BITACORA', 'SP_CONSOLIDAR_CLIENTE', 'SP_ASIGNAR_BLOQUE', 'SP_APLICAR_SUBIDA',
                      'SP_APLICAR_BAJADA', 'SP_CICLO_SYNC', 'SP_CAMBIAR_PRECIO')
ORDER BY object_name;

-- A5. Objetos con errores (no debe devolver filas)
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

-- A6. Enlaces creados (deben aparecer LNK_SUC01 y LNK_SUC02 con la IP de cada una)
SELECT db_link, username, host FROM user_db_links;


-- PARTE B. SUC01 (Ashly, Puntarenas)

-- B1. Probar el enlace (debe devolver 1)
SELECT 1 FROM DUAL@LNK_SUC01;

-- B2. Tablas de SUC01 vistas desde la central (debe devolver 10)
SELECT COUNT(*) AS tablasSuc01 FROM user_tables@LNK_SUC01;

-- B3. Datos de SUC01 vistos desde la central (CLIENTE 3 al inicio, RANGO_FACTURA 1)
SELECT 'CLIENTE' AS tabla, COUNT(*) AS filas FROM CLIENTE@LNK_SUC01
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA@LNK_SUC01
UNION ALL SELECT 'RANGO_FACTURA', COUNT(*) FROM RANGO_FACTURA@LNK_SUC01;

-- B4. Lo que SUC01 tiene pendiente de subir a la central
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA@LNK_SUC01
WHERE destinoSalida = 'CENTRAL' GROUP BY tablaOrigenSalida, estadoSalida;

-- B5. Ejecutar el ciclo de SUC01 (sube clientes y facturas, baja precios y bloques)
EXEC SP_CICLO_SYNC('SUC01');

-- B6. Resultado del ciclo de SUC01 (SUBIDA y BAJADA deben salir OK, DESCARTADO u OMITIDO; nunca ERROR)
SELECT direccionBitacora, tablaAfectadaBitacora, fechaInicioBitacora, resultadoBitacora FROM BITACORA_SYNC
WHERE contraparteBitacora = 'SUC01' ORDER BY idBitacora DESC FETCH FIRST 10 ROWS ONLY;

-- B7. Estado de SUC01 en la central (CONECTADA y con fecha de ultima sincronizacion)
SELECT codigoSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal FROM SUCURSAL WHERE idSucursal = 1;

-- B8. Clientes y facturas de SUC01 que ya llegaron a la central
SELECT COUNT(*) AS clientesSuc01 FROM CLIENTE WHERE idSucursalOrigen = 1;
SELECT idFactura, idClienteLocal, fechaEmisionFactura, totalFactura FROM FACTURA WHERE idSucursalEmisora = 1 ORDER BY idFactura;

-- B9. Envios de la central hacia SUC01 (despues del ciclo no deben quedar PENDIENTE)
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA
WHERE destinoSalida = 'SUC01' GROUP BY tablaOrigenSalida, estadoSalida;

-- B10. Trabajo automatico de SUC01 (solo si ya se corrio 5b_programarSincronizacion)
SELECT job_name, enabled, state, last_start_date, next_run_date FROM user_scheduler_jobs WHERE job_name = 'JOB_SYNC_SUC01';


-- PARTE C. SUC02 (Valeria, Alajuela)

-- C1. Probar el enlace (debe devolver 1)
SELECT 1 FROM DUAL@LNK_SUC02;

-- C2. Tablas de SUC02 vistas desde la central (debe devolver 10)
SELECT COUNT(*) AS tablasSuc02 FROM user_tables@LNK_SUC02;

-- C3. Datos de SUC02 vistos desde la central (CLIENTE 3 al inicio, RANGO_FACTURA 1)
SELECT 'CLIENTE' AS tabla, COUNT(*) AS filas FROM CLIENTE@LNK_SUC02
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA@LNK_SUC02
UNION ALL SELECT 'RANGO_FACTURA', COUNT(*) FROM RANGO_FACTURA@LNK_SUC02;

-- C4. Lo que SUC02 tiene pendiente de subir a la central
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA@LNK_SUC02
WHERE destinoSalida = 'CENTRAL' GROUP BY tablaOrigenSalida, estadoSalida;

-- C5. Ejecutar el ciclo de SUC02
EXEC SP_CICLO_SYNC('SUC02');

-- C6. Resultado del ciclo de SUC02 (nunca ERROR)
SELECT direccionBitacora, tablaAfectadaBitacora, fechaInicioBitacora, resultadoBitacora FROM BITACORA_SYNC
WHERE contraparteBitacora = 'SUC02' ORDER BY idBitacora DESC FETCH FIRST 10 ROWS ONLY;

-- C7. Estado de SUC02 en la central (CONECTADA y con fecha de ultima sincronizacion)
SELECT codigoSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal FROM SUCURSAL WHERE idSucursal = 2;

-- C8. Clientes y facturas de SUC02 que ya llegaron a la central
SELECT COUNT(*) AS clientesSuc02 FROM CLIENTE WHERE idSucursalOrigen = 2;
SELECT idFactura, idClienteLocal, fechaEmisionFactura, totalFactura FROM FACTURA WHERE idSucursalEmisora = 2 ORDER BY idFactura;

-- C9. Envios de la central hacia SUC02 (despues del ciclo no deben quedar PENDIENTE)
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA
WHERE destinoSalida = 'SUC02' GROUP BY tablaOrigenSalida, estadoSalida;

-- C10. Trabajo automatico de SUC02 (solo si ya se corrio 5b_programarSincronizacion)
SELECT job_name, enabled, state, last_start_date, next_run_date FROM user_scheduler_jobs WHERE job_name = 'JOB_SYNC_SUC02';


-- PARTE D. SUC01 Y SUC02 JUNTAS (despues de los dos ciclos)

-- D1. Cliente repetido en las dos sucursales (Maria Rojas Mora debe aparecer como equivalente)
SELECT * FROM CLIENTE_EQUIVALENCIA;

-- D2. Precios iguales en los tres nodos (las tres columnas deben coincidir)
SELECT central.idProducto, central.precioActualProducto AS central,
       suc01.precioActualProducto AS suc01, suc02.precioActualProducto AS suc02
FROM PRODUCTO central
JOIN PRODUCTO@LNK_SUC01 suc01 ON suc01.idProducto = central.idProducto
JOIN PRODUCTO@LNK_SUC02 suc02 ON suc02.idProducto = central.idProducto
ORDER BY central.idProducto;

-- D3. Bloques de facturas de cada sucursal (no deben cruzarse los numeros)
SELECT idSucursal, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA
WHERE idSucursal IN (1, 2) ORDER BY idSucursal, idRango;
