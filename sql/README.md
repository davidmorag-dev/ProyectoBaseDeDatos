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

Cada script de datos se ejecuta una sola vez en una base recien creada.
