# Scripts SQL

Una carpeta por computadora. Cada persona ejecuta solo los archivos de su carpeta.

| Carpeta | Nodo | Modo | Archivos |
|---|---|---|---|
| `CENTRAL` | CENTRAL (David) | Coordinador | `1_instalar`, `2_sincronizacion`, `3_operar` |
| `SUC01` | Puntarenas (Ashly) | Conectada | `1_instalar`, `2_operar` |
| `SUC02` | Alajuela (Valeria) | Conectada | `1_instalar`, `2_operar` |
| `SUC03` | Guanacaste (Fiorella) | Por correo | `1_instalar`, `2_sincronizacion`, `3_operar` |

## Que hace cada archivo

- `1_instalar.sql`: se ejecuta una sola vez en una base recien creada. Crea las 10 tablas, carga los datos iniciales y, en las sucursales, los procedimientos para facturar y guardar clientes sin necesitar red.
- `2_sincronizacion.sql`: todo lo que sincroniza. Es el archivo central del proyecto.
  - CENTRAL: parte A, ciclo de sincronizacion conectada; parte B, recibir el lote de SUC03 y generar su respuesta; parte C, enlaces hacia SUC01 y SUC02 (pide IP, usuario y clave; no guardar claves en Git).
  - SUC03: parte A, generar el lote hacia la central; parte B, aplicar la respuesta de la central.
  - SUC01 y SUC02 no tienen este archivo: en modo conectado quien inicia la sincronizacion es la central.
- `2_operar.sql` / `3_operar.sql`: comprobaciones y operaciones del dia a dia (facturar, ejecutar el ciclo, ver bitacora, activar el programador). Se ejecutan cuantas veces haga falta, un bloque a la vez.

## Orden

1. En los cuatro nodos: `1_instalar.sql`.
2. En CENTRAL y SUC03, un administrador crea antes la carpeta `C:\sync`, el directorio `DIR_SYNC` y el permiso `CREATE JOB` (los comandos estan al inicio de cada `2_sincronizacion.sql`).
3. En CENTRAL y SUC03: `2_sincronizacion.sql`. En CENTRAL la parte C se ejecuta al final, cuando SUC01 y SUC02 ya tienen Oracle accesible por red.
4. En CENTRAL: `3_operar.sql`, seccion 1 para comprobar los enlaces, seccion 2 para el primer ciclo manual y seccion 3 para activar la sincronizacion automatica cada 5 minutos.

## Operaciones frecuentes

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

La central recoge clientes y facturas pendientes, entrega cambios del catalogo y bloques nuevos. `SP_CAMBIAR_PRECIO(1, 455000)` cambia el precio central y deja un envio pendiente para cada sucursal.

Modo por correo (SUC03):

1. SUC03 genera el lote con `EXEC SP_GENERAR_LOTE(FN_SIGUIENTE_LOTE);`, que escribe `lote_SUC03_0001.txt` (tambien lo hace solo `JOB_LOTE_SUC03` a las 8 p. m.).
2. El archivo se envia por correo y se guarda en `C:\sync` de CENTRAL.
3. CENTRAL lo verifica y lo aplica con `EXEC SP_PROCESAR_LOTE('lote_SUC03_0001.txt', 'SUC03');`.
4. CENTRAL genera la respuesta con `EXEC SP_GENERAR_RESPUESTA('SUC03', FN_SIGUIENTE_RESPUESTA('SUC03'));` (tambien lo hace solo `JOB_RESPUESTA_SUC03` a las 9 p. m.). Lleva precios, clientes de otras sucursales, bloques nuevos y acuses.
5. La respuesta se envia por correo, se guarda en `C:\sync` de SUC03 y se aplica con `EXEC SP_PROCESAR_RESPUESTA('respuesta_SUC03_0001.txt', 'SUC03');`.

`PLAN_PRUEBAS.md` propone las diez pruebas de comportamiento y la evidencia que deben guardar para el informe.
