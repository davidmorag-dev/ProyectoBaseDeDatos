-- Ejecutar solo en CENTRAL, despues de 5_sincronizarCentral.sql.
-- Antes, como administrador de la base, crear la carpeta donde se guarda el lote recibido:
--   CREATE DIRECTORY DIR_SYNC AS 'C:\sync';
--   GRANT READ, WRITE ON DIRECTORY DIR_SYNC TO CENTRAL;

-- Devuelve el campo numero pN de un texto. pSeparador va escrito para expresion
-- regular: \| para la barra, ~ y # tal cual.
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

-- Lee un lote enviado por una sucursal en modo diferido, comprueba que llego completo
-- y sin alteraciones, y lo aplica en una sola transaccion.
CREATE OR REPLACE PROCEDURE SP_PROCESAR_LOTE (
    pArchivo IN VARCHAR2,
    pOrigen IN VARCHAR2
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
    idEnvioActual NUMBER;
    tablaActual VARCHAR2(30);
    claveActual VARCHAR2(60);
    versionActual NUMBER;
    datosActuales VARCHAR2(4000);
    resultadoActual VARCHAR2(10);
    existentes NUMBER;
    idSucursalClienteActual NUMBER;
    idClienteLocalActual NUMBER;
    versionCentral NUMBER;
    tipoActual VARCHAR2(10);
    numeroActual VARCHAR2(30);
    nombreActual VARCHAR2(120);
    fechaActual DATE;
    lineaDetalle VARCHAR2(200);
    posicionDetalle NUMBER;
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

    -- Integridad: encabezado, cantidad de envios y huella de cada envio.
    IF cantidadLineas = 0 OR FN_CAMPO(lineas(1), '\|', 1) <> 'ENC'
       OR FN_CAMPO(lineas(1), '\|', 2) <> pOrigen THEN
        RAISE_APPLICATION_ERROR(-20040, 'Encabezado del lote invalido');
    END IF;
    FOR i IN 2 .. cantidadLineas LOOP
        IF FN_CAMPO(lineas(i), '\|', 1) = 'ENV' THEN
            cantidadEnvios := cantidadEnvios + 1;
            IF RAWTOHEX(STANDARD_HASH(FN_CAMPO(lineas(i), '\|', 6), 'SHA256'))
               <> FN_CAMPO(lineas(i), '\|', 7) THEN
                RAISE_APPLICATION_ERROR(-20041, 'Huella distinta en el envio ' ||
                                        FN_CAMPO(lineas(i), '\|', 2));
            END IF;
        END IF;
    END LOOP;
    IF cantidadEnvios <> TO_NUMBER(FN_CAMPO(lineas(1), '\|', 5)) THEN
        RAISE_APPLICATION_ERROR(-20042, 'El lote llego incompleto');
    END IF;

    -- Aplicacion en orden de idSalida; un envio ya recibido se omite.
    FOR i IN 2 .. cantidadLineas LOOP
        IF FN_CAMPO(lineas(i), '\|', 1) = 'ENV' THEN
            idEnvioActual := TO_NUMBER(FN_CAMPO(lineas(i), '\|', 2));
            tablaActual := FN_CAMPO(lineas(i), '\|', 3);
            claveActual := FN_CAMPO(lineas(i), '\|', 4);
            versionActual := TO_NUMBER(FN_CAMPO(lineas(i), '\|', 5));
            datosActuales := FN_CAMPO(lineas(i), '\|', 6);

            SELECT COUNT(*) INTO existentes FROM SYNC_RECIBIDO
            WHERE origenRecibido = pOrigen AND idEnvioRecibido = idEnvioActual;

            IF existentes > 0 THEN
                cantidadOmitidos := cantidadOmitidos + 1;
            ELSE
                resultadoActual := 'APLICADO';

                IF tablaActual = 'CLIENTE' THEN
                    idSucursalClienteActual := TO_NUMBER(SUBSTR(claveActual, 1, INSTR(claveActual, ':') - 1));
                    idClienteLocalActual := TO_NUMBER(SUBSTR(claveActual, INSTR(claveActual, ':') + 1));
                    tipoActual := FN_CAMPO(datosActuales, '~', 1);
                    numeroActual := FN_CAMPO(datosActuales, '~', 2);
                    nombreActual := FN_CAMPO(datosActuales, '~', 3);
                    fechaActual := TO_DATE(FN_CAMPO(datosActuales, '~', 5), 'YYYY-MM-DD HH24:MI:SS');
                    BEGIN
                        SELECT versionCliente INTO versionCentral FROM CLIENTE
                        WHERE idSucursalOrigen = idSucursalClienteActual
                          AND idClienteLocal = idClienteLocalActual;
                        IF versionActual > versionCentral THEN
                            UPDATE CLIENTE SET
                                tipoIdentificacionCliente = tipoActual,
                                numeroIdentificacionCliente = numeroActual,
                                nombreCliente = nombreActual,
                                versionCliente = versionActual,
                                fechaModificacionCliente = fechaActual
                            WHERE idSucursalOrigen = idSucursalClienteActual
                              AND idClienteLocal = idClienteLocalActual;
                        ELSE
                            resultadoActual := 'DESCARTADO';
                        END IF;
                    EXCEPTION WHEN NO_DATA_FOUND THEN
                        INSERT INTO CLIENTE VALUES (
                            idSucursalClienteActual, idClienteLocalActual, tipoActual,
                            numeroActual, nombreActual, versionActual, fechaActual
                        );
                    END;
                    IF resultadoActual = 'APLICADO' THEN
                        SP_CONSOLIDAR_CLIENTE(claveActual, versionActual, tipoActual,
                            numeroActual, idSucursalClienteActual, idClienteLocalActual);
                    END IF;

                ELSIF tablaActual = 'FACTURA' THEN
                    INSERT INTO FACTURA VALUES (
                        TO_NUMBER(claveActual),
                        TO_NUMBER(FN_CAMPO(FN_CAMPO(datosActuales, '#', 1), '~', 1)),
                        TO_NUMBER(FN_CAMPO(FN_CAMPO(datosActuales, '#', 1), '~', 2)),
                        TO_NUMBER(FN_CAMPO(FN_CAMPO(datosActuales, '#', 1), '~', 3)),
                        TO_DATE(FN_CAMPO(FN_CAMPO(datosActuales, '#', 1), '~', 4), 'YYYY-MM-DD HH24:MI:SS'),
                        TO_NUMBER(FN_CAMPO(FN_CAMPO(datosActuales, '#', 1), '~', 5), '999999999990.00')
                    );
                    posicionDetalle := 2;
                    LOOP
                        lineaDetalle := FN_CAMPO(datosActuales, '#', posicionDetalle);
                        EXIT WHEN lineaDetalle IS NULL;
                        INSERT INTO DETALLE_FACTURA VALUES (
                            TO_NUMBER(claveActual),
                            TO_NUMBER(FN_CAMPO(lineaDetalle, '~', 1)),
                            TO_NUMBER(FN_CAMPO(lineaDetalle, '~', 2)),
                            TO_NUMBER(FN_CAMPO(lineaDetalle, '~', 3), '999999999990.00'),
                            TO_NUMBER(FN_CAMPO(lineaDetalle, '~', 4), '999999999990.00')
                        );
                        posicionDetalle := posicionDetalle + 1;
                    END LOOP;

                ELSIF tablaActual = 'RANGO_FACTURA' THEN
                    SP_ASIGNAR_BLOQUE(pOrigen);
                ELSE
                    RAISE_APPLICATION_ERROR(-20043, 'Tipo de envio no reconocido: ' || tablaActual);
                END IF;

                INSERT INTO SYNC_RECIBIDO (
                    origenRecibido, idEnvioRecibido, huellaRecibido,
                    fechaRecepcionRecibido, resultadoRecibido
                ) VALUES (
                    pOrigen, idEnvioActual, FN_CAMPO(lineas(i), '\|', 7), SYSDATE, resultadoActual
                );
                cantidadAplicados := cantidadAplicados + 1;
            END IF;

        ELSIF FN_CAMPO(lineas(i), '\|', 1) = 'ACK' THEN
            UPDATE SYNC_SALIDA SET estadoSalida = 'APLICADO', fechaAplicacionSalida = SYSDATE
            WHERE idSalida = TO_NUMBER(FN_CAMPO(lineas(i), '\|', 2))
              AND destinoSalida = pOrigen AND estadoSalida <> 'APLICADO';
        END IF;
    END LOOP;

    UPDATE SUCURSAL SET fechaUltimaSyncSucursal = SYSDATE WHERE codigoSucursal = pOrigen;
    COMMIT;
    SP_REGISTRAR_BITACORA(pOrigen, 'LOTE_APL', 'LOTE', fechaInicio,
        CASE WHEN cantidadAplicados = 0 AND cantidadOmitidos > 0 THEN 'OMITIDO' ELSE 'OK' END);
EXCEPTION WHEN OTHERS THEN
    IF UTL_FILE.IS_OPEN(archivo) THEN UTL_FILE.FCLOSE(archivo); END IF;
    ROLLBACK;
    SP_REGISTRAR_BITACORA(pOrigen, 'LOTE_APL', 'LOTE', fechaInicio, 'ERROR');
    RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_PROCESAR_LOTE

-- A demanda, al recibir el lote por correo y guardarlo en la carpeta DIR_SYNC:
-- EXEC SP_PROCESAR_LOTE('lote_SUC03_0001.txt', 'SUC03');
