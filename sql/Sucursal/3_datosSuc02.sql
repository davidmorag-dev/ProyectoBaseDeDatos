-- SUC02 (ejecutar solo en SUC02)

-- Solo el bloque asignado por CENTRAL a SUC02.
INSERT INTO RANGO_FACTURA VALUES (2, 2, 1001, 2000, 1001, 'ACTIVO');

-- CLIENTE
INSERT INTO CLIENTE VALUES (2, 1, 'CEDULA', '101110111', 'Maria Rojas Mora', 1, SYSDATE); -- duplicado: tambien esta en SUC01
INSERT INTO CLIENTE VALUES (2, 2, 'CEDULA', '404440444', 'Luis Araya Brenes', 1, SYSDATE);
INSERT INTO CLIENTE VALUES (2, 3, 'CEDULA', '505550555', 'Sofia Mora Leon', 1, SYSDATE);

-- Cada cliente nuevo queda pendiente de subir a CENTRAL.
INSERT INTO SYNC_SALIDA (tablaOrigenSalida, claveRegistroSalida, destinoSalida,
                         versionSalida, estadoSalida, fechaCreacionSalida)
SELECT 'CLIENTE', TO_CHAR(idSucursalOrigen) || ':' || TO_CHAR(idClienteLocal),
       'CENTRAL', versionCliente, 'PENDIENTE', SYSDATE
FROM CLIENTE WHERE idSucursalOrigen = 2;

COMMIT;
