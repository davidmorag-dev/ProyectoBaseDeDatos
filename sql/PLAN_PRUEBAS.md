# Diez pruebas de comportamiento

El enunciado pide diez pruebas documentadas, pero no enumera los diez casos. Estos son los casos que proponemos demostrar. Anotar para cada uno fecha, nodo, comando ejecutado y capturas del estado antes/despues. No ejecutar las pruebas destructivas sobre datos que se quieran conservar.

| # | Accion | Resultado esperado y evidencia |
|---|---|---|
| 1 | Apagar CENTRAL y emitir una factura en cada sucursal. | Cada factura y detalle queda local; el envio queda `PENDIENTE`. Mostrar `FACTURA`, `DETALLE_FACTURA` y `SYNC_SALIDA` en cada nodo. |
| 2 | Levantar CENTRAL y ejecutar `SP_CICLO_SYNC` para SUC01 y SUC02. | Las facturas llegan una vez a CENTRAL y los envios pasan a `APLICADO`. Comparar conteos e identificadores. |
| 3 | Ejecutar otra vez los mismos ciclos sin crear datos nuevos. | No se duplican clientes, facturas ni detalles. Comparar conteos antes/despues. |
| 4 | Desconectar SUC02 e intentar su ciclo mientras SUC01 sigue conectada. | SUC02 queda `SIN_CONEXION`; SUC01 puede sincronizar. La factura local de SUC02 sigue pendiente. |
| 5 | Cambiar un precio en CENTRAL y sincronizar. Para el conflicto, cambiar otro precio en CENTRAL, modificar ese mismo producto en una sucursal de prueba con una fecha posterior y sincronizar. | El primer precio llega a SUC01 y SUC02; SUC03 queda pendiente para correo. En el conflicto, la sucursal descarta el cambio central mas viejo. Comparar `PRODUCTO` y `SYNC_RECIBIDO`. |
| 6 | Intentar guardar un precio negativo o una factura con cantidad no positiva. | Oracle rechaza la operacion y no queda una factura a medias. Mostrar error y conteos antes/despues. |
| 7 | Registrar la misma persona en SUC01 y SUC02 con IDs locales distintos y sincronizar. | CENTRAL conserva ambas llaves y registra la equivalencia; las facturas mantienen su cliente original. Mostrar `CLIENTE_EQUIVALENCIA` y `FACTURA`. |
| 8 | Emitir facturas sin red en las tres sucursales. | Los tres `idFactura` son diferentes porque usan rangos distintos. Mostrar rangos y numeros usados. |
| 9 | Enviar dos versiones de un cliente fuera de orden, primero la nueva y luego la vieja. | Queda la version mas reciente; la vieja se descarta. Mostrar `versionCliente` y `SYNC_RECIBIDO`. Preparar este caso despues de implementar el paquete de SUC03. |
| 10 | Aplicar dos veces el mismo paquete por correo de SUC03. | La segunda aplicacion no duplica datos; el acuse permite marcar el envio como aplicado. Preparar este caso despues de implementar el paquete de SUC03. |

Las pruebas 1, 4 y 8 demuestran autonomia con fallas de red; 3 y 10 demuestran repeticion; 9 demuestra llegada fuera de orden; 6 demuestra rechazo y rollback. Para la demostracion en vivo elegir las mas claras y conservar evidencia de las diez para el informe.
