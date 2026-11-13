-- Ejecutar en SUC01, SUC02 y SUC03 antes de su archivo 3_datosSucXX.sql.
-- Es una copia inicial del catalogo creado en CENTRAL para poder vender sin red.
-- Los cambios posteriores de PRODUCTO deben llegar por sincronizacion.

INSERT INTO SUCURSAL (idSucursal, codigoSucursal, nombreSucursal, modoSyncSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal)
VALUES (1, 'SUC01', 'Sucursal Puntarenas', 'CONECTADO', 'SIN_CONEXION', NULL);
INSERT INTO SUCURSAL (idSucursal, codigoSucursal, nombreSucursal, modoSyncSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal)
VALUES (2, 'SUC02', 'Sucursal Alajuela', 'CONECTADO', 'SIN_CONEXION', NULL);
INSERT INTO SUCURSAL (idSucursal, codigoSucursal, nombreSucursal, modoSyncSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal)
VALUES (3, 'SUC03', 'Sucursal Guanacaste', 'DIFERIDO', 'SIN_CONEXION', NULL);

INSERT INTO PRODUCTO VALUES (1, 'Laptop 15 pulgadas', 450000, DATE '2026-11-01');
INSERT INTO PRODUCTO VALUES (2, 'Computadora de escritorio', 380000, DATE '2026-11-01');
INSERT INTO PRODUCTO VALUES (3, 'Monitor 24 pulgadas', 95000, DATE '2026-11-01');
INSERT INTO PRODUCTO VALUES (4, 'Teclado mecanico', 28000, DATE '2026-11-01');
INSERT INTO PRODUCTO VALUES (5, 'Mouse inalambrico', 9500, DATE '2026-11-01');
INSERT INTO PRODUCTO VALUES (6, 'Audifonos con microfono', 18000, DATE '2026-11-01');
INSERT INTO PRODUCTO VALUES (7, 'Disco SSD 500 GB', 42000, DATE '2026-11-01');
INSERT INTO PRODUCTO VALUES (8, 'Memoria USB 64 GB', 6500, DATE '2026-11-01');
INSERT INTO PRODUCTO VALUES (9, 'Camara web HD', 22000, DATE '2026-11-01');
INSERT INTO PRODUCTO VALUES (10, 'Router WiFi', 31000, DATE '2026-11-01');

COMMIT;
