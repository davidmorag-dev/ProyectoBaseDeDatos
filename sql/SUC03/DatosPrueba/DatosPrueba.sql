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
