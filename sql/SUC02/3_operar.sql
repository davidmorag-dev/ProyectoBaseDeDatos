-- SUC02. Comprobar y operar. Se ejecuta cuantas veces haga falta.
-- La sincronizacion conectada la inicia la CENTRAL (ver CENTRAL/2_sincronizacion.sql).
-- Un bloque a la vez (F9; los EXEC con F5).

-- 0. En cmd:
--    ipconfig
--    lsnrctl status
--    netsh advfirewall firewall show rule name="Oracle1521"

-- 1. Confirmar el usuario y el servicio
SELECT USER AS usuario, SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS servicio,
       SYS_CONTEXT('USERENV', 'SERVER_HOST') AS equipo
FROM DUAL;

-- 2. Las 10 tablas del proyecto (debe devolver 10 filas)
SELECT table_name FROM user_tables
WHERE table_name IN ('SUCURSAL', 'PRODUCTO', 'CLIENTE', 'CLIENTE_EQUIVALENCIA', 'RANGO_FACTURA',
                     'FACTURA', 'DETALLE_FACTURA', 'SYNC_SALIDA', 'SYNC_RECIBIDO', 'BITACORA_SYNC')
ORDER BY table_name;

-- 3. Datos iniciales
SELECT 'SUCURSAL' AS tabla, COUNT(*) AS filas FROM SUCURSAL
UNION ALL SELECT 'PRODUCTO', COUNT(*) FROM PRODUCTO
UNION ALL SELECT 'RANGO_FACTURA', COUNT(*) FROM RANGO_FACTURA
UNION ALL SELECT 'CLIENTE', COUNT(*) FROM CLIENTE
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA;

-- 4. Clientes de esta sucursal
SELECT idSucursalOrigen, idClienteLocal, numeroIdentificacionCliente, nombreCliente, versionCliente
FROM CLIENTE
ORDER BY idClienteLocal;

-- 5. Bloque de facturas propio (debe haber uno ACTIVO)
SELECT idRango, idSucursal, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango
FROM RANGO_FACTURA
ORDER BY idRango;

-- 6. Procedimientos de la sucursal (todos deben salir VALID)
SELECT object_name, object_type, status FROM user_objects
WHERE object_name IN ('SP_SOLICITAR_BLOQUE', 'SP_EMITIR_FACTURA', 'SP_RETIRAR_BLOQUE',
                      'SP_GUARDAR_CLIENTE')
ORDER BY object_name;

-- 7. Objetos con errores (no debe devolver filas)
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

-- 8. Permisos que necesita CENTRAL para entrar por el enlace
SELECT privilege FROM user_sys_privs ORDER BY privilege;

-- 9. Envios hacia CENTRAL y su estado
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad
FROM SYNC_SALIDA
GROUP BY tablaOrigenSalida, estadoSalida
ORDER BY tablaOrigenSalida;

-- 10. Lo que CENTRAL ha bajado a esta sucursal
SELECT origenRecibido, resultadoRecibido, COUNT(*) AS cantidad,
       MAX(fechaRecepcionRecibido) AS ultimo
FROM SYNC_RECIBIDO
GROUP BY origenRecibido, resultadoRecibido;

-- 11. Precios actuales
SELECT idProducto, descripcionProducto, precioActualProducto, fechaModificacionProducto
FROM PRODUCTO
ORDER BY idProducto;

-- 12. Facturas de prueba (se quedan PENDIENTE hasta que la central ejecute el ciclo)
VARIABLE idFactura NUMBER
-- Maria Rojas Mora (tambien en SUC01): una laptop y dos mouse
EXEC SP_EMITIR_FACTURA(2, 2, 1, '[{"idProducto":1,"cantidad":1},{"idProducto":5,"cantidad":2}]', :idFactura);
PRINT idFactura

-- Luis Araya Brenes: un monitor y un teclado
EXEC SP_EMITIR_FACTURA(2, 2, 2, '[{"idProducto":3,"cantidad":1},{"idProducto":4,"cantidad":1}]', :idFactura);
PRINT idFactura

-- Sofia Mora Leon: un router
EXEC SP_EMITIR_FACTURA(2, 2, 3, '[{"idProducto":10,"cantidad":1}]', :idFactura);
PRINT idFactura

-- 13. Ultimas facturas emitidas en esta sucursal
SELECT idFactura, idSucursalCliente, idClienteLocal, fechaEmisionFactura, totalFactura
FROM FACTURA
ORDER BY idFactura DESC
FETCH FIRST 10 ROWS ONLY;
