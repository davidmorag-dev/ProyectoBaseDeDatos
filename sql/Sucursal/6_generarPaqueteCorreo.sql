-- Ejecutar solo en SUC03 (modo diferido), despues de 4_facturarVenta.sql.
-- Antes, como administrador de la base, crear la carpeta donde se guarda el lote:
--   CREATE DIRECTORY DIR_SYNC AS 'C:\sync';
--   GRANT READ, WRITE ON DIRECTORY DIR_SYNC TO SUC03;
-- Los nombres de clientes no deben llevar los simbolos | ni ~ ni #.

CREATE OR REPLACE PROCEDURE SP_REGISTRAR_BITACORA (
    pContraparte IN VARCHAR2,
    pDireccion IN VARCHAR2,
    pTabla IN VARCHAR2,
    pInicio IN DATE,
    pResultado IN VARCHAR2
) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO BITACORA_SYNC (
        contraparteBitacora, direccionBitacora, tablaAfectadaBitacora,
        fechaInicioBitacora, fechaFinBitacora, resultadoBitacora
    ) VALUES (
        pContraparte, pDireccion, pTabla,
        pInicio, SYSDATE, pResultado
    );
    COMMIT;
END;
/
SHOW ERRORS PROCEDURE SP_REGISTRAR_BITACORA

-- Convierte un registro pendiente en una linea de texto.
-- Cliente: tipo~numero~nombre~version~fecha
-- Factura: emisora~sucursalCliente~clienteLocal~fecha~total#linea~producto~cantidad~precio#...
CREATE OR REPLACE FUNCTION FN_SERIALIZAR (
    pTabla IN VARCHAR2,
    pClave IN VARCHAR2
) RETURN VARCHAR2 AS
    datosActuales VARCHAR2(4000);
BEGIN
    IF pTabla = 'CLIENTE' THEN
        SELECT tipoIdentificacionCliente || '~' || numeroIdentificacionCliente || '~' ||
               nombreCliente || '~' || versionCliente || '~' ||
               TO_CHAR(fechaModificacionCliente, 'YYYY-MM-DD HH24:MI:SS')
        INTO datosActuales
        FROM CLIENTE
        WHERE idSucursalOrigen = TO_NUMBER(SUBSTR(pClave, 1, INSTR(pClave, ':') - 1))
          AND idClienteLocal = TO_NUMBER(SUBSTR(pClave, INSTR(pClave, ':') + 1));
    ELSIF pTabla = 'FACTURA' THEN
        SELECT idSucursalEmisora || '~' || idSucursalCliente || '~' || idClienteLocal || '~' ||
               TO_CHAR(fechaEmisionFactura, 'YYYY-MM-DD HH24:MI:SS') || '~' ||
               TO_CHAR(totalFactura, 'FM999999999990.00')
        INTO datosActuales
        FROM FACTURA WHERE idFactura = TO_NUMBER(pClave);
        FOR detalle IN (
            SELECT lineaDetalle, idProducto, cantidadDetalle, precioUnitarioDetalle
            FROM DETALLE_FACTURA WHERE idFactura = TO_NUMBER(pClave)
            ORDER BY lineaDetalle
        ) LOOP
            datosActuales := datosActuales || '#' || detalle.lineaDetalle || '~' ||
                detalle.idProducto || '~' ||
                TO_CHAR(detalle.cantidadDetalle, 'FM999999999990.00') || '~' ||
                TO_CHAR(detalle.precioUnitarioDetalle, 'FM999999999990.00');
        END LOOP;
    ELSE
        datosActuales := '-';
    END IF;
    RETURN datosActuales;
END;
/
SHOW ERRORS FUNCTION FN_SERIALIZAR

CREATE OR REPLACE FUNCTION FN_SIGUIENTE_LOTE RETURN NUMBER AS
    numeroLote NUMBER;
BEGIN
    SELECT COUNT(*) + 1 INTO numeroLote FROM BITACORA_SYNC
    WHERE direccionBitacora = 'LOTE_GEN' AND resultadoBitacora = 'OK';
    RETURN numeroLote;
END;
/
SHOW ERRORS FUNCTION FN_SIGUIENTE_LOTE

-- Escribe el lote: encabezado, un envio por linea con su huella SHA-256 y los acuses.
CREATE OR REPLACE PROCEDURE SP_GENERAR_LOTE (
    pNumeroLote IN NUMBER
) AS
    archivo UTL_FILE.FILE_TYPE;
    fechaInicio DATE := SYSDATE;
    idMaximo NUMBER;
    cantidadEnvios NUMBER;
    datosActuales VARCHAR2(4000);
BEGIN
    SELECT NVL(MAX(idSalida), 0), COUNT(*) INTO idMaximo, cantidadEnvios
    FROM SYNC_SALIDA
    WHERE destinoSalida = 'CENTRAL' AND estadoSalida IN ('PENDIENTE', 'ENVIADO');

    archivo := UTL_FILE.FOPEN('DIR_SYNC',
        'lote_SUC03_' || LPAD(pNumeroLote, 4, '0') || '.txt', 'W', 32767);
    UTL_FILE.PUT_LINE(archivo, 'ENC|SUC03|' || pNumeroLote || '|' ||
        TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') || '|' || cantidadEnvios);

    FOR envio IN (
        SELECT idSalida, tablaOrigenSalida, claveRegistroSalida, versionSalida
        FROM SYNC_SALIDA
        WHERE destinoSalida = 'CENTRAL' AND idSalida <= idMaximo
          AND estadoSalida IN ('PENDIENTE', 'ENVIADO')
        ORDER BY idSalida
    ) LOOP
        datosActuales := FN_SERIALIZAR(envio.tablaOrigenSalida, envio.claveRegistroSalida);
        UTL_FILE.PUT_LINE(archivo, 'ENV|' || envio.idSalida || '|' ||
            envio.tablaOrigenSalida || '|' || envio.claveRegistroSalida || '|' ||
            envio.versionSalida || '|' || datosActuales || '|' ||
            RAWTOHEX(STANDARD_HASH(datosActuales, 'SHA256')));
    END LOOP;

    FOR acuse IN (
        SELECT idEnvioRecibido FROM SYNC_RECIBIDO
        WHERE origenRecibido = 'CENTRAL' ORDER BY idEnvioRecibido
    ) LOOP
        UTL_FILE.PUT_LINE(archivo, 'ACK|' || acuse.idEnvioRecibido);
    END LOOP;
    UTL_FILE.FCLOSE(archivo);

    UPDATE SYNC_SALIDA SET estadoSalida = 'ENVIADO', fechaEnvioSalida = SYSDATE
    WHERE destinoSalida = 'CENTRAL' AND idSalida <= idMaximo
      AND estadoSalida IN ('PENDIENTE', 'ENVIADO');
    COMMIT;
    SP_REGISTRAR_BITACORA('CENTRAL', 'LOTE_GEN', 'LOTE', fechaInicio, 'OK');
EXCEPTION WHEN OTHERS THEN
    IF UTL_FILE.IS_OPEN(archivo) THEN UTL_FILE.FCLOSE(archivo); END IF;
    ROLLBACK;
    SP_REGISTRAR_BITACORA('CENTRAL', 'LOTE_GEN', 'LOTE', fechaInicio, 'ERROR');
    RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_GENERAR_LOTE

-- Genera el lote solo, todos los dias a las 8 p. m.
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'JOB_LOTE_SUC03',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN SP_GENERAR_LOTE(FN_SIGUIENTE_LOTE); END;',
        repeat_interval => 'FREQ=DAILY;BYHOUR=20;BYMINUTE=0',
        enabled         => TRUE);
END;
/

-- A demanda:
-- EXEC SP_GENERAR_LOTE(FN_SIGUIENTE_LOTE);
