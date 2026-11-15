-- Ejecutar solo en CENTRAL. Comprueba la sincronizacion por correo con SUC03 (Fiorella, Guanacaste).
-- SUC03 no tiene enlace: el lote llega por correo y se guarda en C:\sync.
-- Cada bloque se corre por separado (seleccionar y F9; los BEGIN ... END con F5).
SET SERVEROUTPUT ON


-- PARTE A. LA CENTRAL LISTA PARA RECIBIR

-- A1. Confirmar el usuario y el servicio (usuario CENTRAL, servicio XEPDB1)
SELECT USER AS usuario, SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS servicio FROM DUAL;

-- A2. SUC03 registrada en modo DIFERIDO
SELECT idSucursal, codigoSucursal, modoSyncSucursal, estadoConexionSucursal, fechaUltimaSyncSucursal FROM SUCURSAL WHERE idSucursal = 3;

-- A3. Bloque de facturas de SUC03 (del 2001 al 3000)
SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango, estadoRango FROM RANGO_FACTURA WHERE idSucursal = 3;

-- A4. Procedimientos que usa el lote (todos deben salir VALID)
SELECT object_name, object_type, status FROM user_objects
WHERE object_name IN ('FN_CAMPO', 'FN_HUELLA', 'SP_PROCESAR_LOTE', 'SP_REGISTRAR_BITACORA', 'SP_CONSOLIDAR_CLIENTE', 'SP_ASIGNAR_BLOQUE')
ORDER BY object_name;

-- A5. Objetos con errores (no debe devolver filas)
SELECT object_name, object_type, status FROM user_objects WHERE status <> 'VALID';


-- PARTE B. LA CARPETA C:\sync

-- B1. Directorio de Oracle (debe devolver C:\sync)
SELECT directory_name, directory_path FROM all_directories WHERE directory_name = 'DIR_SYNC';

-- B2. Probar que Oracle puede escribir en C:\sync (debe crear C:\sync\prueba_central.txt)
DECLARE
    archivo UTL_FILE.FILE_TYPE;
BEGIN
    archivo := UTL_FILE.FOPEN('DIR_SYNC', 'prueba_central.txt', 'W');
    UTL_FILE.PUT_LINE(archivo, 'Prueba de CENTRAL ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
    UTL_FILE.FCLOSE(archivo);
    DBMS_OUTPUT.PUT_LINE('DIR_SYNC funciona');
END;
/

-- B3. Ver si el lote de Fiorella ya esta en C:\sync (cambiar 0001 si es otro numero)
DECLARE
    existe BOOLEAN;
    tamano NUMBER;
    bloque BINARY_INTEGER;
BEGIN
    UTL_FILE.FGETATTR('DIR_SYNC', 'lote_SUC03_0001.txt', existe, tamano, bloque);
    IF existe THEN
        DBMS_OUTPUT.PUT_LINE('Lote encontrado: ' || tamano || ' bytes');
    ELSE
        DBMS_OUTPUT.PUT_LINE('El lote no esta en C:\sync');
    END IF;
END;
/


-- PARTE C. APLICAR EL LOTE

-- C1. Antes de aplicar: anotar estos conteos para comparar
SELECT (SELECT COUNT(*) FROM CLIENTE WHERE idSucursalOrigen = 3) AS clientesSuc03,
       (SELECT COUNT(*) FROM FACTURA WHERE idSucursalEmisora = 3) AS facturasSuc03,
       (SELECT COUNT(*) FROM SYNC_RECIBIDO WHERE origenRecibido = 'SUC03') AS recibidosSuc03
FROM DUAL;

-- C2. Procesar el lote (cambiar 0001 si es otro numero)
EXEC SP_PROCESAR_LOTE('lote_SUC03_0001.txt', 'SUC03');

-- C3. Despues de aplicar: repetir C1, los conteos deben haber subido
SELECT (SELECT COUNT(*) FROM CLIENTE WHERE idSucursalOrigen = 3) AS clientesSuc03,
       (SELECT COUNT(*) FROM FACTURA WHERE idSucursalEmisora = 3) AS facturasSuc03,
       (SELECT COUNT(*) FROM SYNC_RECIBIDO WHERE origenRecibido = 'SUC03') AS recibidosSuc03
FROM DUAL;

-- C4. Envios de SUC03 recibidos y su resultado (APLICADO o DESCARTADO)
SELECT idEnvioRecibido, huellaRecibido, fechaRecepcionRecibido, resultadoRecibido FROM SYNC_RECIBIDO
WHERE origenRecibido = 'SUC03' ORDER BY idEnvioRecibido;

-- C5. Facturas de SUC03 en la central (numeros del 2001 en adelante)
SELECT idFactura, idClienteLocal, fechaEmisionFactura, totalFactura FROM FACTURA WHERE idSucursalEmisora = 3 ORDER BY idFactura;

-- C6. Detalle de esas facturas
SELECT d.idFactura, d.lineaDetalle, d.idProducto, d.cantidadDetalle, d.precioUnitarioDetalle
FROM DETALLE_FACTURA d JOIN FACTURA f ON f.idFactura = d.idFactura
WHERE f.idSucursalEmisora = 3 ORDER BY d.idFactura, d.lineaDetalle;

-- C7. Registro del lote aplicado (LOTE_APL debe salir OK)
SELECT direccionBitacora, tablaAfectadaBitacora, fechaInicioBitacora, resultadoBitacora FROM BITACORA_SYNC
WHERE contraparteBitacora = 'SUC03' ORDER BY idBitacora DESC FETCH FIRST 10 ROWS ONLY;


-- PARTE D. REPETIR EL MISMO LOTE (prueba 10 del plan)

-- D1. Procesar otra vez el mismo archivo
EXEC SP_PROCESAR_LOTE('lote_SUC03_0001.txt', 'SUC03');

-- D2. Repetir C1: los conteos deben quedar iguales que en C3 (no se duplica nada)
SELECT (SELECT COUNT(*) FROM CLIENTE WHERE idSucursalOrigen = 3) AS clientesSuc03,
       (SELECT COUNT(*) FROM FACTURA WHERE idSucursalEmisora = 3) AS facturasSuc03,
       (SELECT COUNT(*) FROM SYNC_RECIBIDO WHERE origenRecibido = 'SUC03') AS recibidosSuc03
FROM DUAL;


-- PARTE E. LO QUE ESPERA VOLVER A SUC03

-- E1. Envios de la central hacia SUC03 (quedan PENDIENTE hasta que exista el lote de respuesta)
SELECT tablaOrigenSalida, estadoSalida, COUNT(*) AS cantidad FROM SYNC_SALIDA
WHERE destinoSalida = 'SUC03' GROUP BY tablaOrigenSalida, estadoSalida;
