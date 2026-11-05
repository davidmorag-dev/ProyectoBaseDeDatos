-- SUCURSAL
INSERT INTO SUCURSAL (idSucursal, codigoSucursal, nombreSucursal, estadoConexionSucursal) VALUES (1, 'SUC01', 'Sucursal Puntarenas', 'CONECTADA');
INSERT INTO SUCURSAL (idSucursal, codigoSucursal, nombreSucursal, estadoConexionSucursal) VALUES (2, 'SUC02', 'Sucursal Alajuela', 'CONECTADA');
INSERT INTO SUCURSAL (idSucursal, codigoSucursal, nombreSucursal, estadoConexionSucursal) VALUES (3, 'SUC03', 'Sucursal Guanacaste', 'DIFERIDA');

-- PRODUCTO
INSERT INTO PRODUCTO (idProducto, nombreProducto, precioActualProducto, fechaModificacionProducto) VALUES (1, 'Laptop 15 pulgadas', 450000, SYSDATE);
INSERT INTO PRODUCTO (idProducto, nombreProducto, precioActualProducto, fechaModificacionProducto) VALUES (2, 'Computadora de escritorio', 380000, SYSDATE);
INSERT INTO PRODUCTO (idProducto, nombreProducto, precioActualProducto, fechaModificacionProducto) VALUES (3, 'Monitor 24 pulgadas', 95000, SYSDATE);
INSERT INTO PRODUCTO (idProducto, nombreProducto, precioActualProducto, fechaModificacionProducto) VALUES (4, 'Teclado mecanico', 28000, SYSDATE);
INSERT INTO PRODUCTO (idProducto, nombreProducto, precioActualProducto, fechaModificacionProducto) VALUES (5, 'Mouse inalambrico', 9500, SYSDATE);
INSERT INTO PRODUCTO (idProducto, nombreProducto, precioActualProducto, fechaModificacionProducto) VALUES (6, 'Audifonos con microfono', 18000, SYSDATE);
INSERT INTO PRODUCTO (idProducto, nombreProducto, precioActualProducto, fechaModificacionProducto) VALUES (7, 'Disco SSD 500 GB', 42000, SYSDATE);
INSERT INTO PRODUCTO (idProducto, nombreProducto, precioActualProducto, fechaModificacionProducto) VALUES (8, 'Memoria USB 64 GB', 6500, SYSDATE);
INSERT INTO PRODUCTO (idProducto, nombreProducto, precioActualProducto, fechaModificacionProducto) VALUES (9, 'Camara web HD', 22000, SYSDATE);
INSERT INTO PRODUCTO (idProducto, nombreProducto, precioActualProducto, fechaModificacionProducto) VALUES (10, 'Router WiFi', 31000, SYSDATE);

-- RANGO_FACTURA
INSERT INTO RANGO_FACTURA (idRango, idSucursal, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango) VALUES (1, 1, 1, 1000, 1, 'ACTIVO');
INSERT INTO RANGO_FACTURA (idRango, idSucursal, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango) VALUES (2, 2, 1001, 2000, 1001, 'ACTIVO');
INSERT INTO RANGO_FACTURA (idRango, idSucursal, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango) VALUES (3, 3, 2001, 2005, 2001, 'ACTIVO');

COMMIT;
