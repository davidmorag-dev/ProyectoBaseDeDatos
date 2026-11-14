-- Ejecutar solo en SUC02, despues de 4_facturarVenta.sql. Cada ejecucion crea 3 facturas nuevas.
-- SP_EMITIR_FACTURA(sucursal emisora, sucursal del cliente, cliente local, detalles, factura)

VARIABLE idFactura NUMBER

-- Maria Rojas Mora (tambien en SUC01): una laptop y dos mouse
EXEC SP_EMITIR_FACTURA(2, 2, 1, '[{"idProducto":1,"cantidad":1},{"idProducto":5,"cantidad":2}]', :idFactura);
PRINT idFactura

-- Luis Araya Brenes: un monitor y un teclado
EXEC SP_EMITIR_FACTURA(2, 2, 2, '[{"idProducto":3,"cantidad":1},{"idProducto":4,"cantidad":1}]', :idFactura);
PRINT idFactura

-- Sofia Mora Leon: un router
EXEC SP_EMITIR_FACTURA(2, 2, 3, '[{"idProducto":10,"cantidad":1}]', :idFactura);
PRINT idFactura

-- Facturas locales y su envio pendiente hacia CENTRAL
SELECT idFactura, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;
SELECT idSalida, claveRegistroSalida, estadoSalida FROM SYNC_SALIDA WHERE tablaOrigenSalida = 'FACTURA';
