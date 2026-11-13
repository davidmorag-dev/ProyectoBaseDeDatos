# Scripts SQL

| Carpeta | Se ejecuta en |
|---|---|
| Conjunto | Los 4 nodos (CENTRAL, SUC01, SUC02, SUC03) |
| Central | Solo la central |
| Sucursal | Las tres usan `2_catalogoInicialSucursal.sql` y cada una ejecuta solo su `3_datosSucXX.sql` |

## Orden de carga inicial

1. En los cuatro nodos: `Conjunto/1_crearTablas.sql`.
2. En CENTRAL: `Central/2_datosCentral.sql`.
3. En SUC01, SUC02 y SUC03: `Sucursal/2_catalogoInicialSucursal.sql`. Esta es una copia inicial del catalogo central para que puedan vender sin red; los cambios posteriores deben sincronizarse.
4. En cada sucursal: su propio `Sucursal/3_datosSucXX.sql`, que carga solo su bloque, sus clientes y los envios pendientes hacia CENTRAL.
5. En cada sucursal: `Sucursal/4_facturarVenta.sql` y `Sucursal/5_sincronizarSucursal.sql`.
6. En CENTRAL: `Central/4_configurarEnlaces.sql`, cuando SUC01 y SUC02 ya tengan Oracle accesible por red. El script pide sus IP, usuarios y claves; no guardar claves en Git.
   Para mostrar el estado de las dos conexiones antes y despues de sincronizar, ejecutar `Central/4b_verificarConexiones.sql` en CENTRAL. Se puede repetir; SUC03 aparece como modo correo.
7. En CENTRAL: `Central/5_sincronizarCentral.sql`.
8. En CENTRAL: `Central/5b_programarSincronizacion.sql` crea los trabajos que ejecutan `SP_CICLO_SYNC` cada 5 minutos para SUC01 y SUC02.
9. Modo por correo (SUC03). Un administrador crea antes la carpeta `DIR_SYNC` en SUC03 y en CENTRAL.
   - En SUC03: `Sucursal/6_generarPaqueteCorreo.sql`; `EXEC SP_GENERAR_LOTE(FN_SIGUIENTE_LOTE);` escribe el archivo `lote_SUC03_0001.txt`.
   - Ese archivo se envia por correo y se guarda en la carpeta `DIR_SYNC` de CENTRAL.
   - En CENTRAL: `Central/6_aplicarPaqueteCorreo.sql`; `EXEC SP_PROCESAR_LOTE('lote_SUC03_0001.txt', 'SUC03');` verifica el lote y lo aplica.
   - Falta el lote de respuesta de CENTRAL hacia SUC03.

Cada script de datos se ejecuta una sola vez en una base recien creada.

`SP_EMITIR_FACTURA` recibe los detalles como JSON. Ejemplo para SUC01:

```sql
VARIABLE idFactura NUMBER
EXEC SP_EMITIR_FACTURA(1, 1, 1, '[{"idProducto":1,"cantidad":1},{"idProducto":5,"cantidad":2}]', :idFactura);
PRINT idFactura
```

La factura y sus detalles se guardan localmente aunque CENTRAL este apagada. Su fila en `SYNC_SALIDA` queda PENDIENTE hasta ejecutar el ciclo desde CENTRAL.

Para crear o actualizar un cliente en SUC01, usar un `idClienteLocal` libre de esa sucursal:

```sql
EXEC SP_GUARDAR_CLIENTE(1, 4, 'CEDULA', '404440444', 'Nuevo Cliente');
```

Cuando SUC01 y SUC02 esten conectadas, ejecutar en CENTRAL:

```sql
EXEC SP_CICLO_SYNC('SUC01');
EXEC SP_CICLO_SYNC('SUC02');
```

La central recoge clientes y facturas pendientes, entrega cambios del catalogo y bloques nuevos. `SP_CAMBIAR_PRECIO(1, 455000)` cambia el precio central y deja un envio pendiente para cada sucursal. SUC03 usa el modo diferido; su paquete por correo todavia no esta implementado. Estos procedimientos no se han ejecutado aun en las cuatro computadoras.

Despues de ambos ciclos, `Central/8_consultasDemostracion.sql` muestra facturas, envios pendientes, clientes equivalentes y precios de los dos enlaces conectados.

`PLAN_PRUEBAS.md` propone las diez pruebas de comportamiento y la evidencia que deben guardar para el informe.
