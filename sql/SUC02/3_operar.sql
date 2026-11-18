-- SUC02. Comprobar y operar. Se ejecuta cuantas veces haga falta, un bloque a la vez (F9, y los EXEC con F5).
-- La sincronizacion la inicia la CENTRAL con SP_CICLO_SYNC; aqui se ve lo que queda pendiente y lo que se aplico.
SET SERVEROUTPUT ON

-- 1. objetos con errores (no debe devolver filas)
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';

-- 2. datos iniciales
SELECT 'PRODUCTO' AS tabla, COUNT(*) AS filas FROM PRODUCTO
UNION ALL SELECT 'CLIENTE', COUNT(*) FROM CLIENTE
UNION ALL SELECT 'FACTURA', COUNT(*) FROM FACTURA;

-- 3. bloque de numeracion propio
SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA;

-- 4. facturar (funciona aunque la central este apagada). El detalle va como producto:cantidad;producto:cantidad
VARIABLE idFactura NUMBER
-- Maria Rojas Mora (tambien en SUC01)
EXEC SP_EMITIR_FACTURA(2, 2, 1, '1:1;5:2', :idFactura);
PRINT idFactura

-- Luis Araya Brenes
EXEC SP_EMITIR_FACTURA(2, 2, 2, '3:1;4:1', :idFactura);
PRINT idFactura

-- Sofia Mora Leon
EXEC SP_EMITIR_FACTURA(2, 2, 3, '10:1', :idFactura);
PRINT idFactura

-- 5. facturas emitidas y envios pendientes hacia la central
SELECT idFactura, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

-- 6. guardar un cliente nuevo (queda pendiente para la central)
EXEC SP_GUARDAR_CLIENTE(2, 4, 'CEDULA', '808880888', 'Pedro Quesada Mora');

-- 7. despues del ciclo de la central: los envios deben salir APLICADO
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA GROUP BY tablaOrigenSalida, estadoSalida;

-- 8. lo que la central entrego a esta sucursal
SELECT origenRecibido, resultadoRecibido, COUNT(*) AS cantidad FROM SYNC_RECIBIDO GROUP BY origenRecibido, resultadoRecibido;
SELECT idProducto, precioActualProducto FROM PRODUCTO ORDER BY idProducto;

SELECT COUNT(*) FROM FACTURA;


