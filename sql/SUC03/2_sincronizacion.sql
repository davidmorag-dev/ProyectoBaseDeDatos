-- SUC03. Sincronizacion por correo. Se ejecuta despues de 1_instalar.sql.
-- Antes, como SYSTEM en XEPDB1:
--   CREATE DIRECTORY DIR_SYNC AS 'C:\sync';
--   GRANT READ, WRITE ON DIRECTORY DIR_SYNC TO SUC03;
--   GRANT CREATE JOB TO SUC03;
-- Los nombres de clientes no deben llevar los simbolos | ~ #.


-- PARTE A. GENERAR EL LOTE HACIA LA CENTRAL

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

-- Convierte un registro en una linea de texto
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

CREATE OR REPLACE FUNCTION FN_HUELLA (
    pTexto IN VARCHAR2
) RETURN VARCHAR2 AS
    huellaActual VARCHAR2(64);
BEGIN
    SELECT RAWTOHEX(STANDARD_HASH(pTexto, 'SHA256')) INTO huellaActual FROM DUAL;
    RETURN huellaActual;
END;
/
SHOW ERRORS FUNCTION FN_HUELLA

-- Escribe el lote con sus envios y acuses
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
            FN_HUELLA(datosActuales));
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

-- Genera el lote todos los dias a las 8 p. m.
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'JOB_LOTE_SUC03',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN SP_GENERAR_LOTE(FN_SIGUIENTE_LOTE); END;',
        repeat_interval => 'FREQ=DAILY;BYHOUR=20;BYMINUTE=0',
        enabled         => TRUE);
END;
/

-- EXEC SP_GENERAR_LOTE(FN_SIGUIENTE_LOTE);


-- PARTE B. APLICAR LA RESPUESTA DE LA CENTRAL

-- Devuelve el campo pN de un texto
CREATE OR REPLACE FUNCTION FN_CAMPO (
    pTexto IN VARCHAR2,
    pSeparador IN VARCHAR2,
    pN IN NUMBER
) RETURN VARCHAR2 AS
BEGIN
    RETURN REGEXP_SUBSTR(pTexto, '([^' || pSeparador || ']*)(' || pSeparador || '|$)',
                         1, pN, NULL, 1);
END;
/
SHOW ERRORS FUNCTION FN_CAMPO

-- Lee la respuesta de la central y la aplica
CREATE OR REPLACE PROCEDURE SP_PROCESAR_RESPUESTA (
    pArchivo IN VARCHAR2,
    pSucursal IN VARCHAR2
) AS
    TYPE tLineas IS TABLE OF VARCHAR2(4000) INDEX BY PLS_INTEGER;
    lineas tLineas;
    archivo UTL_FILE.FILE_TYPE;
    lineaActual VARCHAR2(4000);
    cantidadLineas PLS_INTEGER := 0;
    cantidadEnvios NUMBER := 0;
    cantidadAplicados NUMBER := 0;
    cantidadOmitidos NUMBER := 0;
    fechaInicio DATE := SYSDATE;
    idSucursalPropia NUMBER := TO_NUMBER(SUBSTR(pSucursal, 4));
    idEnvioActual NUMBER;
    tablaActual VARCHAR2(30);
    claveActual VARCHAR2(60);
    versionActual NUMBER;
    datosActuales VARCHAR2(4000);
    resultadoActual VARCHAR2(10);
    existentes NUMBER;
    fechaLocal DATE;
    fechaRecibida DATE;
    versionLocal NUMBER;
    idSucursalClienteActual NUMBER;
    idClienteLocalActual NUMBER;
BEGIN
    archivo := UTL_FILE.FOPEN('DIR_SYNC', pArchivo, 'R', 32767);
    BEGIN
        LOOP
            UTL_FILE.GET_LINE(archivo, lineaActual);
            cantidadLineas := cantidadLineas + 1;
            lineas(cantidadLineas) := lineaActual;
        END LOOP;
    EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
    END;
    UTL_FILE.FCLOSE(archivo);

    -- Validar la respuesta
    IF cantidadLineas = 0 OR FN_CAMPO(lineas(1), '\|', 1) <> 'ENC'
       OR FN_CAMPO(lineas(1), '\|', 2) <> 'CENTRAL'
       OR NVL(FN_CAMPO(lineas(1), '\|', 6), '-') <> pSucursal THEN
        RAISE_APPLICATION_ERROR(-20060, 'Encabezado de la respuesta invalido');
    END IF;
    FOR i IN 2 .. cantidadLineas LOOP
        IF FN_CAMPO(lineas(i), '\|', 1) = 'ENV' THEN
            cantidadEnvios := cantidadEnvios + 1;
            IF FN_HUELLA(FN_CAMPO(lineas(i), '\|', 6)) <> FN_CAMPO(lineas(i), '\|', 7) THEN
                RAISE_APPLICATION_ERROR(-20061, 'Huella distinta en el envio ' ||
                                        FN_CAMPO(lineas(i), '\|', 2));
            END IF;
        END IF;
    END LOOP;
    IF cantidadEnvios <> TO_NUMBER(FN_CAMPO(lineas(1), '\|', 5)) THEN
        RAISE_APPLICATION_ERROR(-20062, 'La respuesta llego incompleta');
    END IF;

    -- Aplicar los envios
    FOR i IN 2 .. cantidadLineas LOOP
        IF FN_CAMPO(lineas(i), '\|', 1) = 'ENV' THEN
            idEnvioActual := TO_NUMBER(FN_CAMPO(lineas(i), '\|', 2));
            tablaActual := FN_CAMPO(lineas(i), '\|', 3);
            claveActual := FN_CAMPO(lineas(i), '\|', 4);
            versionActual := TO_NUMBER(FN_CAMPO(lineas(i), '\|', 5));
            datosActuales := FN_CAMPO(lineas(i), '\|', 6);

            SELECT COUNT(*) INTO existentes FROM SYNC_RECIBIDO
            WHERE origenRecibido = 'CENTRAL' AND idEnvioRecibido = idEnvioActual;

            IF existentes > 0 THEN
                cantidadOmitidos := cantidadOmitidos + 1;
            ELSE
                resultadoActual := 'APLICADO';

                IF tablaActual = 'PRODUCTO' THEN
                    -- Gana el cambio mas reciente
                    fechaRecibida := TO_DATE(FN_CAMPO(datosActuales, '~', 3), 'YYYY-MM-DD HH24:MI:SS');
                    BEGIN
                        SELECT fechaModificacionProducto INTO fechaLocal FROM PRODUCTO
                        WHERE idProducto = TO_NUMBER(claveActual);
                        IF fechaRecibida > fechaLocal THEN
                            UPDATE PRODUCTO SET
                                descripcionProducto = FN_CAMPO(datosActuales, '~', 1),
                                precioActualProducto = TO_NUMBER(FN_CAMPO(datosActuales, '~', 2), '999999999990.00'),
                                fechaModificacionProducto = fechaRecibida
                            WHERE idProducto = TO_NUMBER(claveActual);
                        ELSE
                            resultadoActual := 'DESCARTADO';
                        END IF;
                    EXCEPTION WHEN NO_DATA_FOUND THEN
                        INSERT INTO PRODUCTO VALUES (
                            TO_NUMBER(claveActual),
                            FN_CAMPO(datosActuales, '~', 1),
                            TO_NUMBER(FN_CAMPO(datosActuales, '~', 2), '999999999990.00'),
                            fechaRecibida
                        );
                    END;

                ELSIF tablaActual = 'CLIENTE' THEN
                    idSucursalClienteActual := TO_NUMBER(SUBSTR(claveActual, 1, INSTR(claveActual, ':') - 1));
                    idClienteLocalActual := TO_NUMBER(SUBSTR(claveActual, INSTR(claveActual, ':') + 1));
                    -- Los clientes propios se descartan
                    IF idSucursalClienteActual = idSucursalPropia THEN
                        resultadoActual := 'DESCARTADO';
                    ELSE
                        BEGIN
                            SELECT versionCliente INTO versionLocal FROM CLIENTE
                            WHERE idSucursalOrigen = idSucursalClienteActual
                              AND idClienteLocal = idClienteLocalActual;
                            IF versionActual > versionLocal THEN
                                UPDATE CLIENTE SET
                                    tipoIdentificacionCliente = FN_CAMPO(datosActuales, '~', 1),
                                    numeroIdentificacionCliente = FN_CAMPO(datosActuales, '~', 2),
                                    nombreCliente = FN_CAMPO(datosActuales, '~', 3),
                                    versionCliente = versionActual,
                                    fechaModificacionCliente = TO_DATE(FN_CAMPO(datosActuales, '~', 5), 'YYYY-MM-DD HH24:MI:SS')
                                WHERE idSucursalOrigen = idSucursalClienteActual
                                  AND idClienteLocal = idClienteLocalActual;
                            ELSE
                                resultadoActual := 'DESCARTADO';
                            END IF;
                        EXCEPTION WHEN NO_DATA_FOUND THEN
                            INSERT INTO CLIENTE VALUES (
                                idSucursalClienteActual, idClienteLocalActual,
                                FN_CAMPO(datosActuales, '~', 1),
                                FN_CAMPO(datosActuales, '~', 2),
                                FN_CAMPO(datosActuales, '~', 3),
                                versionActual,
                                TO_DATE(FN_CAMPO(datosActuales, '~', 5), 'YYYY-MM-DD HH24:MI:SS')
                            );
                        END;
                    END IF;

                ELSIF tablaActual = 'RANGO_FACTURA' THEN
                    SELECT COUNT(*) INTO existentes FROM RANGO_FACTURA
                    WHERE idRango = TO_NUMBER(claveActual);
                    IF existentes = 0 THEN
                        INSERT INTO RANGO_FACTURA VALUES (
                            TO_NUMBER(claveActual),
                            TO_NUMBER(FN_CAMPO(datosActuales, '~', 1)),
                            TO_NUMBER(FN_CAMPO(datosActuales, '~', 2)),
                            TO_NUMBER(FN_CAMPO(datosActuales, '~', 3)),
                            TO_NUMBER(FN_CAMPO(datosActuales, '~', 4)),
                            FN_CAMPO(datosActuales, '~', 5)
                        );
                    ELSE
                        resultadoActual := 'DESCARTADO';
                    END IF;
                ELSE
                    RAISE_APPLICATION_ERROR(-20063, 'Tipo de envio no reconocido: ' || tablaActual);
                END IF;

                INSERT INTO SYNC_RECIBIDO (
                    origenRecibido, idEnvioRecibido, huellaRecibido,
                    fechaRecepcionRecibido, resultadoRecibido
                ) VALUES (
                    'CENTRAL', idEnvioActual, FN_CAMPO(lineas(i), '\|', 7), SYSDATE, resultadoActual
                );
                cantidadAplicados := cantidadAplicados + 1;
            END IF;

        ELSIF FN_CAMPO(lineas(i), '\|', 1) = 'ACK' THEN
            -- Acuse de la central
            UPDATE SYNC_SALIDA SET estadoSalida = 'APLICADO', fechaAplicacionSalida = SYSDATE
            WHERE idSalida = TO_NUMBER(FN_CAMPO(lineas(i), '\|', 2))
              AND destinoSalida = 'CENTRAL' AND estadoSalida <> 'APLICADO';
        END IF;
    END LOOP;

    UPDATE SUCURSAL SET fechaUltimaSyncSucursal = SYSDATE WHERE codigoSucursal = pSucursal;
    COMMIT;
    SP_REGISTRAR_BITACORA('CENTRAL', 'LOTE_APL', 'LOTE', fechaInicio,
        CASE WHEN cantidadAplicados = 0 AND cantidadOmitidos > 0 THEN 'OMITIDO' ELSE 'OK' END);
EXCEPTION WHEN OTHERS THEN
    IF UTL_FILE.IS_OPEN(archivo) THEN UTL_FILE.FCLOSE(archivo); END IF;
    ROLLBACK;
    SP_REGISTRAR_BITACORA('CENTRAL', 'LOTE_APL', 'LOTE', fechaInicio, 'ERROR');
    RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_PROCESAR_RESPUESTA

-- EXEC SP_PROCESAR_RESPUESTA('respuesta_SUC03_0001.txt', 'SUC03');
