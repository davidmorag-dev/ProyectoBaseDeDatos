-- Ejecutar solo en SUC03, despues de 4_facturarVenta.sql. Cada ejecucion crea 2 facturas nuevas.
-- SUC03 no tiene enlace: sus facturas quedan PENDIENTE hasta generar el lote (6_generarPaqueteCorreo.sql).

VARIABLE idFactura NUMBER

-- Jorge Castro Perez: un SSD y una memoria USB
EXEC SP_EMITIR_FACTURA(3, 3, 1, '[{"idProducto":7,"cantidad":1},{"idProducto":8,"cantidad":2}]', :idFactura);
PRINT idFactura

-- Laura Solis Vega: unos audifonos y una camara web
EXEC SP_EMITIR_FACTURA(3, 3, 2, '[{"idProducto":6,"cantidad":1},{"idProducto":9,"cantidad":1}]', :idFactura);
PRINT idFactura

-- Facturas locales y su envio pendiente hacia CENTRAL
SELECT idFactura, idClienteLocal, totalFactura FROM FACTURA ORDER BY idFactura;
SELECT idSalida, claveRegistroSalida, estadoSalida FROM SYNC_SALIDA WHERE tablaOrigenSalida = 'FACTURA';

-- Para enviarlas: EXEC SP_GENERAR_LOTE(FN_SIGUIENTE_LOTE);
