-- SUC02. Datos de prueba para la demostracion. Se corre un bloque a la vez (F9, y los EXEC con F5).
-- Todo se hace con los procedimientos (no con INSERT) para que quede el envio pendiente y se consuma el bloque de numeracion.
-- Despues de cada bloque la central ejecuta el ciclo (CENTRAL/3_operar.sql, bloque 5) y aqui se revisa el resultado.
SET SERVEROUTPUT ON
VARIABLE idFactura NUMBER

-- 1. dos clientes nuevos
EXEC SP_GUARDAR_CLIENTE(2, 5, 'CEDULA', '322220001', 'Andrea Cruz Mora');
EXEC SP_GUARDAR_CLIENTE(2, 6, 'CEDULA', '322220002', 'Diego Pineda Soto');
SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 2 ORDER BY idClienteLocal;
SELECT idSucursalOrigen, idClienteLocal, nombreCliente, numeroIdentificacionCliente, versionCliente
FROM CLIENTE
ORDER BY idSucursalOrigen, idClienteLocal;

-- 2. dos facturas con varias lineas (producto:cantidad;producto:cantidad)
EXEC SP_EMITIR_FACTURA(2, 2, 5, '2:1;7:2', :idFactura);
PRINT idFactura
EXEC SP_EMITIR_FACTURA(2, 2, 6, '4:1;10:3;5:2', :idFactura);
PRINT idFactura
SELECT idFactura, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;

-- 3. una persona que ya esta registrada en otra sucursal (la central la detecta por la cedula)
EXEC SP_GUARDAR_CLIENTE(2, 7, 'CEDULA', '112233445', 'Nuevo Cliente');

-- 4. modificar un cliente: sube la version y viaja a todos los nodos
EXEC SP_GUARDAR_CLIENTE(2, 5, 'CEDULA', '322220001', 'Andrea Cruz Mora Modificado');
SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 2 ORDER BY idClienteLocal;

-- 5. cosas que Oracle debe rechazar (no queda nada a medias)
-- cantidad cero
EXEC SP_EMITIR_FACTURA(2, 2, 5, '1:0', :idFactura);
-- borrar un cliente que ya tiene facturas
DELETE FROM CLIENTE WHERE idSucursalOrigen = 2 AND idClienteLocal = 5;

-- 6. lo que queda pendiente de enviar a la central
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

------------------------------------------------------------------------------------------------------------



-- 7. diez facturas mas, para los clientes propios de SUC02 (producto:cantidad;producto:cantidad)
VARIABLE idFactura NUMBER
EXEC SP_EMITIR_FACTURA(2, 2, 1, '2:1;8:1', :idFactura);
EXEC SP_EMITIR_FACTURA(2, 2, 2, '6:3', :idFactura);
EXEC SP_EMITIR_FACTURA(2, 2, 3, '1:1;9:2', :idFactura);
EXEC SP_EMITIR_FACTURA(2, 2, 1, '4:2;5:1', :idFactura);
EXEC SP_EMITIR_FACTURA(2, 2, 2, '10:1;7:1', :idFactura);
EXEC SP_EMITIR_FACTURA(2, 2, 3, '3:1', :idFactura);
EXEC SP_EMITIR_FACTURA(2, 2, 1, '8:5', :idFactura);
EXEC SP_EMITIR_FACTURA(2, 2, 2, '2:1;6:1', :idFactura);
EXEC SP_EMITIR_FACTURA(2, 2, 3, '5:3;9:1;4:1', :idFactura);
EXEC SP_EMITIR_FACTURA(2, 2, 1, '7:2', :idFactura);
SELECT idFactura, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;

-- 8. diez clientes nuevos de SUC02
EXEC SP_GUARDAR_CLIENTE(2, 8, 'CEDULA', '322220003', 'Sebastian Rojas Leon');
EXEC SP_GUARDAR_CLIENTE(2, 9, 'CEDULA', '322220004', 'Carolina Vega Murillo');
EXEC SP_GUARDAR_CLIENTE(2, 10, 'CEDULA', '322220005', 'Daniel Chacon Araya');
EXEC SP_GUARDAR_CLIENTE(2, 11, 'CEDULA', '322220006', 'Mariana Solano Bonilla');
EXEC SP_GUARDAR_CLIENTE(2, 12, 'CEDULA', '322220007', 'Pablo Esquivel Rojas');
EXEC SP_GUARDAR_CLIENTE(2, 13, 'CEDULA', '322220008', 'Laura Montero Fallas');
EXEC SP_GUARDAR_CLIENTE(2, 14, 'CEDULA', '322220009', 'Kevin Arguedas Mora');
EXEC SP_GUARDAR_CLIENTE(2, 15, 'CEDULA', '322220010', 'Silvia Cordero Ramirez');
EXEC SP_GUARDAR_CLIENTE(2, 16, 'CEDULA', '322220011', 'Jorge Brenes Castro');
EXEC SP_GUARDAR_CLIENTE(2, 17, 'CEDULA', '322220012', 'Daniela Picado Ulloa');
SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 2 ORDER BY idClienteLocal;

-- 9. clientes repetidos: las mismas tres personas se registran en SUC01, SUC02 y SUC03 (la central las detecta por la cedula)
EXEC SP_GUARDAR_CLIENTE(2, 20, 'CEDULA', '900000001', 'Roberto Castillo Vargas');
EXEC SP_GUARDAR_CLIENTE(2, 21, 'CEDULA', '900000002', 'Monica Urena Soto');
EXEC SP_GUARDAR_CLIENTE(2, 22, 'CEDULA', '900000003', 'Javier Quesada Alpizar');
SELECT idClienteLocal, nombreCliente, numeroIdentificacionCliente FROM CLIENTE WHERE idSucursalOrigen = 2 AND idClienteLocal >= 20;
