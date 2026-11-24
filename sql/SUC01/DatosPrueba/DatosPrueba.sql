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

------------------------------------------------------------------------------------------------------------



-- 7. diez facturas mas, para los clientes propios de SUC01 (producto:cantidad;producto:cantidad)
VARIABLE idFactura NUMBER
EXEC SP_EMITIR_FACTURA(1, 1, 1, '1:1;5:1', :idFactura);
EXEC SP_EMITIR_FACTURA(1, 1, 2, '3:2', :idFactura);
EXEC SP_EMITIR_FACTURA(1, 1, 3, '7:1;8:3', :idFactura);
EXEC SP_EMITIR_FACTURA(1, 1, 1, '2:1', :idFactura);
EXEC SP_EMITIR_FACTURA(1, 1, 2, '4:1;6:1;9:1', :idFactura);
EXEC SP_EMITIR_FACTURA(1, 1, 3, '10:2', :idFactura);
EXEC SP_EMITIR_FACTURA(1, 1, 1, '5:4;8:2', :idFactura);
EXEC SP_EMITIR_FACTURA(1, 1, 2, '1:1;3:1', :idFactura);
EXEC SP_EMITIR_FACTURA(1, 1, 3, '6:2;9:1', :idFactura);
EXEC SP_EMITIR_FACTURA(1, 1, 1, '7:2;10:1', :idFactura);
SELECT idFactura, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;

-- 8. diez clientes nuevos de SUC01
EXEC SP_GUARDAR_CLIENTE(1, 8, 'CEDULA', '311110003', 'Marco Alfaro Chaves');
EXEC SP_GUARDAR_CLIENTE(1, 9, 'CEDULA', '311110004', 'Paula Herrera Quiros');
EXEC SP_GUARDAR_CLIENTE(1, 10, 'CEDULA', '311110005', 'Jose Navarro Ulate');
EXEC SP_GUARDAR_CLIENTE(1, 11, 'CEDULA', '311110006', 'Valeria Campos Arias');
EXEC SP_GUARDAR_CLIENTE(1, 12, 'CEDULA', '311110007', 'Ricardo Salazar Mena');
EXEC SP_GUARDAR_CLIENTE(1, 13, 'CEDULA', '311110008', 'Fernanda Rojas Calvo');
EXEC SP_GUARDAR_CLIENTE(1, 14, 'CEDULA', '311110009', 'Andres Mora Villalobos');
EXEC SP_GUARDAR_CLIENTE(1, 15, 'CEDULA', '311110010', 'Gabriela Sanchez Brenes');
EXEC SP_GUARDAR_CLIENTE(1, 16, 'CEDULA', '311110011', 'Luis Fernandez Solis');
EXEC SP_GUARDAR_CLIENTE(1, 17, 'CEDULA', '311110012', 'Natalia Jimenez Porras');
SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 1 ORDER BY idClienteLocal;

-- 9. clientes repetidos: las mismas tres personas se registran en SUC01, SUC02 y SUC03 (la central las detecta por la cedula)
EXEC SP_GUARDAR_CLIENTE(1, 20, 'CEDULA', '900000001', 'Roberto Castillo Vargas');
EXEC SP_GUARDAR_CLIENTE(1, 21, 'CEDULA', '900000002', 'Monica Urena Soto');
EXEC SP_GUARDAR_CLIENTE(1, 22, 'CEDULA', '900000003', 'Javier Quesada Alpizar');
SELECT idClienteLocal, nombreCliente, numeroIdentificacionCliente FROM CLIENTE WHERE idSucursalOrigen = 1 AND idClienteLocal >= 20;
