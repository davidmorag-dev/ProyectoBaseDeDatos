-- CENTRAL. Datos de prueba para la demostracion. Se corre un bloque a la vez (F9, y los EXEC con F5).
SET SERVEROUTPUT ON

-- 1. cambiar dos precios en la central
EXEC SP_CAMBIAR_PRECIO(3, 99000);
EXEC SP_CAMBIAR_PRECIO(6, 19500);

-- 2. sincronizar con las sucursales conectadas
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');

-- 3. los precios nuevos deben verse igual en los tres nodos
SELECT p.idProducto, p.precioActualProducto AS central, s1.precioActualProducto AS suc01, s2.precioActualProducto AS suc02
FROM PRODUCTO p
JOIN PRODUCTO@LNK_SUC01 s1 ON s1.idProducto = p.idProducto
JOIN PRODUCTO@LNK_SUC02 s2 ON s2.idProducto = p.idProducto
WHERE p.idProducto IN (3, 6);

-- 4. despues de que las sucursales carguen sus datos (DatosPrueba de cada una) y se sincronice:
SELECT idSucursalOrigen, COUNT(*) AS clientes FROM CLIENTE GROUP BY idSucursalOrigen;
SELECT * FROM CLIENTE_EQUIVALENCIA;
SELECT s.codigoSucursal, COUNT(*) AS facturas, SUM(f.totalFactura) AS totalVendido
FROM FACTURA f JOIN SUCURSAL s ON s.idSucursal = f.idSucursalEmisora
GROUP BY s.codigoSucursal ORDER BY s.codigoSucursal;

-- 5. cosas que Oracle debe rechazar
-- precio negativo
EXEC SP_CAMBIAR_PRECIO(1, -5);
-- producto que no existe
EXEC SP_CAMBIAR_PRECIO(99, 100);
