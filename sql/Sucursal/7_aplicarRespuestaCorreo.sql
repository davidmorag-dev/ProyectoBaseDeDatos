-- Ejecutar solo en SUC03 (modo diferido), despues de 6_generarPaqueteCorreo.sql.
-- Aplica la respuesta que la central manda por correo; el archivo debe estar en DIR_SYNC.

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

-- Lee la respuesta de la central, comprueba que llego completa y sin alteraciones,
-- y la aplica en una sola transaccion.
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

    -- Integridad: encabezado, destino, cantidad de envios y huella de cada envio.
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

    -- Aplicacion en orden de idSalida; un envio ya recibido se omite.
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
                    -- Gana el cambio mas reciente: uno viejo de la central se descarta.
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
                    -- Los clientes propios ya estan aqui: la sucursal es su duena.
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
            -- La central confirma un envio de esta sucursal: ya no se vuelve a mandar.
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

-- A demanda, al recibir la respuesta por correo y guardarla en la carpeta DIR_SYNC:
-- EXEC SP_PROCESAR_RESPUESTA('respuesta_SUC03_0001.txt', 'SUC03');
