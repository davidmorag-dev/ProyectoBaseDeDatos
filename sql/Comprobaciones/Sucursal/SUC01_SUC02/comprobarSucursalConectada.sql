-- Ejecutar en SUC01 (Ashly) o en SUC02 (Valeria), cada una en su propia base.
-- Cada bloque se corre por separado (seleccionar y F9) para ir comprobando.

-- 0. Antes de Oracle, en cmd (fuera de SQL Developer):
--    ipconfig                -> copiar la Direccion IPv4 del Wi-Fi y mandarla a CENTRAL
--    lsnrctl status          -> debe aparecer el servicio XEPDB1
--    netsh advfirewall firewall show rule name="Oracle1521"   -> la regla del puerto 1521 debe existir

-- 1. Confirmar el usuario y el servicio (el servicio debe ser XEPDB1)
SELECT USER AS usuario, SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS servicio, SYS_CONTEXT('USERENV', 'SERVER_HOST') AS equipo FROM DUAL;

-- 2. Las 10 tablas del proyecto (debe devolver 10 filas)
SELECT table_name FROM user_tables
WHERE table_name IN ('SUCURSAL', 'PRODUCTO', 'CLIENTE', 'CLIENTE_EQUIVALENCIA', 'RANGO_FACTURA',
                     'FACTURA', 'DETALLE_FACTURA', 'SYNC_SALIDA', 'SYNC_RECIBIDO', 'BITACORA_SYNC')
ORDER BY table_name;

-- 3. Datos iniciales (SUCURSAL 3, PRODUCTO 10, RANGO_FACTURA 1, CLIENTE 3)
SELECT 'SUCURSAL' AS tabla, COUNT(*) AS filas FROM SUCURSAL
UNION ALL SELECT 'PRODUCTO', COUNT(*) FROM PRODUCTO
UNION ALL SELECT 'RANGO_FACTURA', COUNT(*) FROM RANGO_FACTURA
UNION ALL SELECT 'CLIENTE', COUNT(*) FROM CLIENTE
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA;

-- 4. Clientes de esta sucursal (todos con el idSucursalOrigen propio: 1 en SUC01, 2 en SUC02)
SELECT idSucursalOrigen, idClienteLocal, numeroIdentificacionCliente, nombreCliente, versionCliente FROM CLIENTE ORDER BY idClienteLocal;

-- 5. Bloque de facturas propio (debe haber uno ACTIVO)
SELECT idRango, idSucursal, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA ORDER BY idRango;

-- 6. Procedimientos de la sucursal (todos deben salir VALID)
SELECT object_name, object_type, status FROM user_objects
WHERE object_name IN ('SP_SOLICITAR_BLOQUE', 'SP_EMITIR_FACTURA', 'SP_RETIRAR_BLOQUE', 'SP_GUARDAR_CLIENTE')
ORDER BY object_name;

-- 7. Objetos con errores (no debe devolver filas)
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

-- 8. Permisos que necesita CENTRAL para entrar por el enlace (CREATE SESSION como minimo)
SELECT privilege FROM user_sys_privs ORDER BY privilege;

-- 9. Envios hacia CENTRAL y su estado (despues de un ciclo deben pasar de PENDIENTE a APLICADO)
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida ORDER BY tablaOrigenSalida;

-- 10. Lo que CENTRAL ha bajado a esta sucursal (prueba de que el enlace entro)
SELECT origenRecibido, resultadoRecibido, COUNT(*) AS cantidad, MAX(fechaRecepcionRecibido) AS ultimo FROM SYNC_RECIBIDO GROUP BY origenRecibido, resultadoRecibido;

-- 11. Precios actuales (comparar con CENTRAL despues de un cambio de precio)
SELECT idProducto, descripcionProducto, precioActualProducto, fechaModificacionProducto FROM PRODUCTO ORDER BY idProducto;

-- 12. Factura de prueba, solo cuando CENTRAL lo pida. En SUC02 cambiar (1, 1, 1 por (2, 2, 1
VARIABLE idFactura NUMBER
EXEC SP_EMITIR_FACTURA(1, 1, 1, '[{"idProducto":1,"cantidad":1}]', :idFactura);
PRINT idFactura

-- 13. Ultimas facturas emitidas en esta sucursal
SELECT idFactura, idSucursalCliente, idClienteLocal, fechaEmisionFactura, totalFactura FROM FACTURA ORDER BY idFactura DESC FETCH FIRST 10 ROWS ONLY;
