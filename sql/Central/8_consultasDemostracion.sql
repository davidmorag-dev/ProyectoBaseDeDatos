-- Ejecutar en CENTRAL despues de configurar los enlaces y correr ambos ciclos.
-- Son consultas de lectura: no cambian datos.

PROMPT === Estado de las sucursales ===
SELECT codigoSucursal, modoSyncSucursal, estadoConexionSucursal,
       fechaUltimaSyncSucursal
FROM SUCURSAL ORDER BY idSucursal;

PROMPT === Facturas recibidas por sucursal ===
SELECT idSucursalEmisora, COUNT(*) AS cantidadFacturas,
       SUM(totalFactura) AS totalVendido
FROM FACTURA GROUP BY idSucursalEmisora ORDER BY idSucursalEmisora;

PROMPT === Ventas por sucursal en un periodo ===
-- :desde y :hasta son fechas, por ejemplo DATE '2026-11-01' y DATE '2026-12-01'.
SELECT s.codigoSucursal AS sucursal, COUNT(*) AS facturas,
       SUM(f.totalFactura) AS totalVendido
FROM FACTURA f
JOIN SUCURSAL s ON s.idSucursal = f.idSucursalEmisora
WHERE f.fechaEmisionFactura >= :desde AND f.fechaEmisionFactura < :hasta
GROUP BY s.codigoSucursal
ORDER BY s.codigoSucursal;

PROMPT === Envios centrales pendientes ===
SELECT destinoSalida, tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad
FROM SYNC_SALIDA
GROUP BY destinoSalida, tablaOrigenSalida, estadoSalida
ORDER BY destinoSalida, tablaOrigenSalida, estadoSalida;

PROMPT === Recepciones y descartes en CENTRAL ===
SELECT origenRecibido, resultadoRecibido, COUNT(*) AS cantidad
FROM SYNC_RECIBIDO
GROUP BY origenRecibido, resultadoRecibido
ORDER BY origenRecibido, resultadoRecibido;

PROMPT === Clientes duplicados detectados ===
SELECT idSucursalOrigen, idClienteLocal,
       idSucursalCanonica, idClienteCanonico
FROM CLIENTE_EQUIVALENCIA
ORDER BY idSucursalOrigen, idClienteLocal;

PROMPT === Comparacion de precios entre CENTRAL, SUC01 y SUC02 ===
SELECT central.idProducto, central.precioActualProducto AS precioCentral,
       suc01.precioActualProducto AS precioSuc01,
       suc02.precioActualProducto AS precioSuc02
FROM PRODUCTO central
JOIN PRODUCTO@LNK_SUC01 suc01 ON suc01.idProducto = central.idProducto
JOIN PRODUCTO@LNK_SUC02 suc02 ON suc02.idProducto = central.idProducto
ORDER BY central.idProducto;
