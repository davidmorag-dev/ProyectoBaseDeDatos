-- SUC03 (ejecutar solo en SUC03)

-- Solo el bloque asignado por CENTRAL a SUC03.
INSERT INTO RANGO_FACTURA VALUES (3, 3, 2001, 3000, 2001, 'ACTIVO');

-- CLIENTE
INSERT INTO CLIENTE VALUES (3, 1, 'CEDULA', '606660666', 'Jorge Castro Perez', 1, SYSDATE);
INSERT INTO CLIENTE VALUES (3, 2, 'CEDULA', '707770777', 'Laura Solis Vega', 1, SYSDATE);

-- Los pendientes de SUC03 viajaran en el paquete por correo.
INSERT INTO SYNC_SALIDA (tablaOrigenSalida, claveRegistroSalida, destinoSalida,
                         versionSalida, estadoSalida, fechaCreacionSalida)
SELECT 'CLIENTE', TO_CHAR(idSucursalOrigen) || ':' || TO_CHAR(idClienteLocal),
       'CENTRAL', versionCliente, 'PENDIENTE', SYSDATE
FROM CLIENTE WHERE idSucursalOrigen = 3;

COMMIT;
