-- SUC03. Datos de prueba para la demostracion. Se corre un bloque a la vez (F9, y los EXEC con F5).
-- Todo se hace con los procedimientos (no con INSERT) para que quede el envio pendiente y se consuma el bloque de numeracion.
-- Despues de cada bloque la central ejecuta el ciclo (CENTRAL/3_operar.sql, bloque 5) y aqui se revisa el resultado.
SET SERVEROUTPUT ON
VARIABLE idFactura NUMBER

-- 1. dos clientes nuevos
EXEC SP_GUARDAR_CLIENTE(3, 4, 'CEDULA', '333330001', 'Karla Vega Lopez');
EXEC SP_GUARDAR_CLIENTE(3, 5, 'CEDULA', '333330002', 'Esteban Leiva Mora');
SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 3 ORDER BY idClienteLocal;

-- 2. dos facturas con varias lineas (producto:cantidad;producto:cantidad)
EXEC SP_EMITIR_FACTURA(3, 3, 4, '2:1;7:2', :idFactura);
PRINT idFactura
EXEC SP_EMITIR_FACTURA(3, 3, 5, '4:1;10:3;5:2', :idFactura);
PRINT idFactura
SELECT idFactura, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;

-- 3. una persona que ya esta registrada en otra sucursal (la central la detecta por la cedula)
EXEC SP_GUARDAR_CLIENTE(3, 6, 'CEDULA', '311110001', 'Daniela Mora Vega');

-- 4. modificar un cliente: sube la version y viaja a todos los nodos
EXEC SP_GUARDAR_CLIENTE(3, 4, 'CEDULA', '333330001', 'Karla Vega Lopez Modificado');
SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 3 ORDER BY idClienteLocal;

-- 5. cosas que Oracle debe rechazar (no queda nada a medias)
-- cantidad cero
EXEC SP_EMITIR_FACTURA(3, 3, 4, '1:0', :idFactura);
-- borrar un cliente que ya tiene facturas
DELETE FROM CLIENTE WHERE idSucursalOrigen = 3 AND idClienteLocal = 4;

-- 6. lo que queda pendiente de enviar a la central
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

-- 7. generar el lote para la central (queda en C:\sync y se envia por correo)
EXEC SP_GENERAR_PAQUETE('SUC03', 'CENTRAL', FN_SIGUIENTE_PAQUETE('CENTRAL'));

------------------------------------------------------------------------------------------------------------



-- 8. diez facturas mas, para los clientes propios de SUC03 (producto:cantidad;producto:cantidad)
VARIABLE idFactura NUMBER
EXEC SP_EMITIR_FACTURA(3, 3, 1, '9:1;5:2', :idFactura);
EXEC SP_EMITIR_FACTURA(3, 3, 2, '1:1', :idFactura);
EXEC SP_EMITIR_FACTURA(3, 3, 1, '4:1;8:2', :idFactura);
EXEC SP_EMITIR_FACTURA(3, 3, 2, '3:1;6:2', :idFactura);
EXEC SP_EMITIR_FACTURA(3, 3, 1, '10:1;7:1', :idFactura);
EXEC SP_EMITIR_FACTURA(3, 3, 2, '2:1;9:1', :idFactura);
EXEC SP_EMITIR_FACTURA(3, 3, 1, '5:5', :idFactura);
EXEC SP_EMITIR_FACTURA(3, 3, 2, '8:3;4:1', :idFactura);
EXEC SP_EMITIR_FACTURA(3, 3, 1, '6:1;7:2', :idFactura);
EXEC SP_EMITIR_FACTURA(3, 3, 2, '3:2;10:1', :idFactura);
SELECT idFactura, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;

-- 9. diez clientes nuevos de SUC03
EXEC SP_GUARDAR_CLIENTE(3, 7, 'CEDULA', '333330003', 'Adrian Matarrita Guevara');
EXEC SP_GUARDAR_CLIENTE(3, 8, 'CEDULA', '333330004', 'Yesenia Obando Ruiz');
EXEC SP_GUARDAR_CLIENTE(3, 9, 'CEDULA', '333330005', 'Mauricio Alvarado Pizarro');
EXEC SP_GUARDAR_CLIENTE(3, 10, 'CEDULA', '333330006', 'Rebeca Carrillo Espinoza');
EXEC SP_GUARDAR_CLIENTE(3, 11, 'CEDULA', '333330007', 'Fabian Viales Contreras');
EXEC SP_GUARDAR_CLIENTE(3, 12, 'CEDULA', '333330008', 'Tatiana Baltodano Lara');
EXEC SP_GUARDAR_CLIENTE(3, 13, 'CEDULA', '333330009', 'Randall Gutierrez Rosales');
EXEC SP_GUARDAR_CLIENTE(3, 14, 'CEDULA', '333330010', 'Priscilla Moraga Chavarria');
EXEC SP_GUARDAR_CLIENTE(3, 15, 'CEDULA', '333330011', 'Esteban Juarez Cubillo');
EXEC SP_GUARDAR_CLIENTE(3, 16, 'CEDULA', '333330012', 'Karina Angulo Barrantes');
SELECT idClienteLocal, nombreCliente, versionCliente FROM CLIENTE WHERE idSucursalOrigen = 3 ORDER BY idClienteLocal;

-- 10. clientes repetidos: las mismas tres personas se registran en SUC01, SUC02 y SUC03 (la central las detecta por la cedula)
EXEC SP_GUARDAR_CLIENTE(3, 20, 'CEDULA', '900000001', 'Roberto Castillo Vargas');
EXEC SP_GUARDAR_CLIENTE(3, 21, 'CEDULA', '900000002', 'Monica Urena Soto');
EXEC SP_GUARDAR_CLIENTE(3, 22, 'CEDULA', '900000003', 'Javier Quesada Alpizar');
SELECT idClienteLocal, nombreCliente, numeroIdentificacionCliente FROM CLIENTE WHERE idSucursalOrigen = 3 AND idClienteLocal >= 20;
