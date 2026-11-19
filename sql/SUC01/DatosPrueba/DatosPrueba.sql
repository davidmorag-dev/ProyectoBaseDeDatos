-- SUC01. Datos de prueba para la demostracion. Se corre un bloque a la vez (F9, y los EXEC con F5).
-- Todo se hace con los procedimientos (no con INSERT) para que quede el envio pendiente y se consuma el bloque de numeracion.
-- Despues de cada bloque la central ejecuta el ciclo (CENTRAL/3_operar.sql, bloque 5) y aqui se revisa el resultado.
SET SERVEROUTPUT ON
VARIABLE idFactura NUMBER

-- 1. dos clientes nuevos
EXEC SP_GUARDAR_CLIENTE(1, 5, 'CEDULA', '311110001', 'Daniela Mora Vega');
EXEC SP_GUARDAR_CLIENTE(1, 6, 'CEDULA', '311110002', 'Kevin Solano Rojas');
SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 1 ORDER BY idClienteLocal;

-- 2. dos facturas con varias lineas (producto:cantidad;producto:cantidad)
EXEC SP_EMITIR_FACTURA(1, 1, 5, '2:1;7:2', :idFactura);
PRINT idFactura
EXEC SP_EMITIR_FACTURA(1, 1, 6, '4:1;10:3;5:2', :idFactura);
PRINT idFactura
SELECT idFactura, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;

-- 3. una persona que ya esta registrada en otra sucursal (la central la detecta por la cedula)
EXEC SP_GUARDAR_CLIENTE(1, 7, 'CEDULA', '808880888', 'Pedro Quesada Mora');

-- 4. modificar un cliente: sube la version y viaja a todos los nodos
EXEC SP_GUARDAR_CLIENTE(1, 5, 'CEDULA', '311110001', 'Daniela Mora Vega Modificado');
SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 1 ORDER BY idClienteLocal;

-- 5. cosas que Oracle debe rechazar (no queda nada a medias)
-- cantidad cero
EXEC SP_EMITIR_FACTURA(1, 1, 5, '1:0', :idFactura);
-- borrar un cliente que ya tiene facturas
DELETE FROM CLIENTE WHERE idSucursalOrigen = 1 AND idClienteLocal = 5;

-- 6. lo que queda pendiente de enviar a la central
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;
