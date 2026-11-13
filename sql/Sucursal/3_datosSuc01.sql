-- SUC01 (ejecutar solo en SUC01)

-- Solo el bloque asignado por CENTRAL a SUC01.
INSERT INTO RANGO_FACTURA VALUES (1, 1, 1, 1000, 1, 'ACTIVO');

-- CLIENTE
INSERT INTO CLIENTE VALUES (1, 1, 'CEDULA', '101110111', 'Maria Rojas Mora', 1, SYSDATE); -- tambien esta en SUC02
INSERT INTO CLIENTE VALUES (1, 2, 'CEDULA', '202220222', 'Carlos Vargas Soto', 1, SYSDATE);
INSERT INTO CLIENTE VALUES (1, 3, 'CEDULA', '303330333', 'Ana Jimenez Cruz', 1, SYSDATE);

-- Cada cliente nuevo queda pendiente de subir a CENTRAL.
INSERT INTO SYNC_SALIDA (tablaOrigenSalida, claveRegistroSalida, destinoSalida,
                         versionSalida, estadoSalida, fechaCreacionSalida)
SELECT 'CLIENTE', TO_CHAR(idSucursalOrigen) || ':' || TO_CHAR(idClienteLocal),
       'CENTRAL', versionCliente, 'PENDIENTE', SYSDATE
FROM CLIENTE WHERE idSucursalOrigen = 1;

COMMIT;
