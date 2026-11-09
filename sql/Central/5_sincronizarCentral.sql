-- Ejecutar solo en CENTRAL, despues de crear LNK_SUC01 y LNK_SUC02.
-- La central inicia los ciclos; las sucursales siguen facturando sin ella.

CREATE OR REPLACE PROCEDURE SP_REGISTRAR_BITACORA (
    pContraparte IN VARCHAR2,
    pDireccion IN VARCHAR2,
    pTabla IN VARCHAR2,
    pInicio IN TIMESTAMP,
    pResultado IN VARCHAR2
) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO BITACORA_SYNC (
        contraparteBitacora, direccionBitacora, tablaAfectadaBitacora,
        fechaInicioBitacora, fechaFinBitacora, resultadoBitacora
    ) VALUES (
        pContraparte, pDireccion, pTabla,
        pInicio, SYSTIMESTAMP, pResultado
    );
    COMMIT;
END;
/
SHOW ERRORS PROCEDURE SP_REGISTRAR_BITACORA

CREATE OR REPLACE PROCEDURE SP_APLICAR_SUBIDA (
    pEnlace IN VARCHAR2,
    pSucursal IN VARCHAR2,
    pIdSalida IN NUMBER,
    pTabla IN VARCHAR2,
    pClave IN VARCHAR2,
    pVersion IN NUMBER
) AS
    fechaInicio TIMESTAMP := SYSTIMESTAMP;
    cantidadRecibidos NUMBER;
    resultadoRecibidoActual VARCHAR2(10) := 'APLICADO';
    huellaActual VARCHAR2(64);
    idSucursalClienteActual NUMBER;
    idClienteLocalActual NUMBER;
    tipoIdentificacionActual VARCHAR2(10);
    numeroIdentificacionActual VARCHAR2(30);
    nombreClienteActual VARCHAR2(120);
    versionClienteActual NUMBER;
    fechaModificacionActual TIMESTAMP;
    versionCentral NUMBER;
    idSucursalCanonicaActual NUMBER;
    idClienteCanonicoActual NUMBER;
    idRangoNuevo NUMBER;
    numeroInicialNuevo NUMBER;
BEGIN
    SELECT COUNT(*) INTO cantidadRecibidos FROM SYNC_RECIBIDO
    WHERE origenRecibido = pSucursal AND idEnvioRecibido = pIdSalida;
    IF cantidadRecibidos > 0 THEN
        EXECUTE IMMEDIATE 'UPDATE SYNC_SALIDA@' || pEnlace ||
            ' SET estadoSalida = ''APLICADO'', fechaAplicacionSalida = SYSTIMESTAMP WHERE idSalida = :1'
            USING pIdSalida;
        COMMIT;
        SP_REGISTRAR_BITACORA(pSucursal, 'SUBIDA', pTabla, fechaInicio, 'OMITIDO');
        RETURN;
    END IF;

    SELECT RAWTOHEX(STANDARD_HASH(pTabla || '|' || pClave || '|' || pVersion, 'SHA256'))
    INTO huellaActual FROM DUAL;

    IF pTabla = 'CLIENTE' THEN
        idSucursalClienteActual := TO_NUMBER(SUBSTR(pClave, 1, INSTR(pClave, ':') - 1));
        idClienteLocalActual := TO_NUMBER(SUBSTR(pClave, INSTR(pClave, ':') + 1));
        EXECUTE IMMEDIATE 'SELECT tipoIdentificacionCliente, numeroIdentificacionCliente, nombreCliente, ' ||
            'versionCliente, fechaModificacionCliente FROM CLIENTE@' || pEnlace ||
            ' WHERE idSucursalOrigen = :1 AND idClienteLocal = :2'
            INTO tipoIdentificacionActual, numeroIdentificacionActual, nombreClienteActual,
                 versionClienteActual, fechaModificacionActual
            USING idSucursalClienteActual, idClienteLocalActual;

        BEGIN
            SELECT versionCliente INTO versionCentral FROM CLIENTE
            WHERE idSucursalOrigen = idSucursalClienteActual
              AND idClienteLocal = idClienteLocalActual;
            IF versionClienteActual > versionCentral THEN
                UPDATE CLIENTE SET
                    tipoIdentificacionCliente = tipoIdentificacionActual,
                    numeroIdentificacionCliente = numeroIdentificacionActual,
                    nombreCliente = nombreClienteActual,
                    versionCliente = versionClienteActual,
                    fechaModificacionCliente = fechaModificacionActual
                WHERE idSucursalOrigen = idSucursalClienteActual
                  AND idClienteLocal = idClienteLocalActual;
            ELSE
                resultadoRecibidoActual := 'DESCARTADO';
            END IF;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            INSERT INTO CLIENTE (
                idSucursalOrigen, idClienteLocal, tipoIdentificacionCliente,
                numeroIdentificacionCliente, nombreCliente, versionCliente,
                fechaModificacionCliente
            ) VALUES (
                idSucursalClienteActual, idClienteLocalActual, tipoIdentificacionActual,
                numeroIdentificacionActual, nombreClienteActual, versionClienteActual,
                fechaModificacionActual
            );
        END;

        IF resultadoRecibidoActual = 'APLICADO' THEN
            INSERT INTO SYNC_SALIDA (
                tablaOrigenSalida, claveRegistroSalida, destinoSalida,
                versionSalida, estadoSalida, fechaCreacionSalida
            )
            SELECT 'CLIENTE', pClave, codigoSucursal,
                   versionClienteActual, 'PENDIENTE', SYSTIMESTAMP
            FROM SUCURSAL;

            SELECT idSucursalOrigen, idClienteLocal
            INTO idSucursalCanonicaActual, idClienteCanonicoActual
            FROM (
                SELECT idSucursalOrigen, idClienteLocal
                FROM CLIENTE
                WHERE tipoIdentificacionCliente = tipoIdentificacionActual
                  AND numeroIdentificacionCliente = numeroIdentificacionActual
                ORDER BY fechaModificacionCliente, idSucursalOrigen, idClienteLocal
            ) WHERE ROWNUM = 1;

            FOR clienteDuplicado IN (
                SELECT idSucursalOrigen, idClienteLocal FROM CLIENTE
                WHERE tipoIdentificacionCliente = tipoIdentificacionActual
                  AND numeroIdentificacionCliente = numeroIdentificacionActual
                  AND (idSucursalOrigen <> idSucursalCanonicaActual
                       OR idClienteLocal <> idClienteCanonicoActual)
            ) LOOP
                MERGE INTO CLIENTE_EQUIVALENCIA equivalencia
                USING DUAL ON (
                    equivalencia.idSucursalOrigen = clienteDuplicado.idSucursalOrigen
                    AND equivalencia.idClienteLocal = clienteDuplicado.idClienteLocal
                )
                WHEN MATCHED THEN UPDATE SET
                    idSucursalCanonica = idSucursalCanonicaActual,
                    idClienteCanonico = idClienteCanonicoActual
                WHEN NOT MATCHED THEN INSERT (
                    idSucursalOrigen, idClienteLocal, idSucursalCanonica,
                    idClienteCanonico, fechaDeteccionEquivalencia
                ) VALUES (
                    clienteDuplicado.idSucursalOrigen, clienteDuplicado.idClienteLocal,
                    idSucursalCanonicaActual, idClienteCanonicoActual, SYSTIMESTAMP
                );
            END LOOP;
        END IF;

    ELSIF pTabla = 'FACTURA' THEN
        EXECUTE IMMEDIATE 'INSERT INTO FACTURA SELECT * FROM FACTURA@' || pEnlace ||
            ' WHERE idFactura = :1' USING TO_NUMBER(pClave);
        EXECUTE IMMEDIATE 'INSERT INTO DETALLE_FACTURA SELECT * FROM DETALLE_FACTURA@' || pEnlace ||
            ' WHERE idFactura = :1' USING TO_NUMBER(pClave);

    ELSIF pTabla = 'RANGO_FACTURA' THEN
        -- La solicitud local del 80 % pide un bloque nuevo; el contador solo vive en la sucursal.
        LOCK TABLE RANGO_FACTURA IN EXCLUSIVE MODE;
        SELECT NVL(MAX(idRango), 0) + 1, NVL(MAX(numeroFinalRango), 0) + 1
        INTO idRangoNuevo, numeroInicialNuevo FROM RANGO_FACTURA;
        INSERT INTO RANGO_FACTURA VALUES (
            idRangoNuevo, TO_NUMBER(SUBSTR(pSucursal, 4)),
            numeroInicialNuevo, numeroInicialNuevo + 999,
            numeroInicialNuevo, 'ACTIVO'
        );
        INSERT INTO SYNC_SALIDA (
            tablaOrigenSalida, claveRegistroSalida, destinoSalida,
            versionSalida, estadoSalida, fechaCreacionSalida
        ) VALUES (
            'RANGO_FACTURA', TO_CHAR(idRangoNuevo), pSucursal,
            1, 'PENDIENTE', SYSTIMESTAMP
        );
    ELSE
        RAISE_APPLICATION_ERROR(-20020, 'Tipo de subida no reconocido: ' || pTabla);
    END IF;

    INSERT INTO SYNC_RECIBIDO (
        origenRecibido, idEnvioRecibido, huellaRecibido,
        fechaRecepcionRecibido, resultadoRecibido
    ) VALUES (
        pSucursal, pIdSalida, huellaActual, SYSTIMESTAMP, resultadoRecibidoActual
    );
    EXECUTE IMMEDIATE 'UPDATE SYNC_SALIDA@' || pEnlace ||
        ' SET estadoSalida = ''APLICADO'', fechaAplicacionSalida = SYSTIMESTAMP WHERE idSalida = :1'
        USING pIdSalida;
    COMMIT;
    SP_REGISTRAR_BITACORA(pSucursal, 'SUBIDA', pTabla, fechaInicio,
                         CASE resultadoRecibidoActual WHEN 'APLICADO' THEN 'OK'
                              ELSE resultadoRecibidoActual END);
EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    SP_REGISTRAR_BITACORA(pSucursal, 'SUBIDA', pTabla, fechaInicio, 'ERROR');
    RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_APLICAR_SUBIDA

CREATE OR REPLACE PROCEDURE SP_APLICAR_BAJADA (
    pEnlace IN VARCHAR2,
    pSucursal IN VARCHAR2,
    pIdSalida IN NUMBER,
    pTabla IN VARCHAR2,
    pClave IN VARCHAR2,
    pVersion IN NUMBER
) AS
    fechaInicio TIMESTAMP := SYSTIMESTAMP;
    cantidadRecibidos NUMBER;
    resultadoRecibidoActual VARCHAR2(10) := 'APLICADO';
    huellaActual VARCHAR2(64);
    idProductoActual NUMBER;
    codigoProductoActual VARCHAR2(30);
    descripcionProductoActual VARCHAR2(200);
    precioActual NUMBER(12,2);
    fechaProductoActual TIMESTAMP;
    fechaProductoRemoto TIMESTAMP;
    idSucursalClienteActual NUMBER;
    idClienteLocalActual NUMBER;
    tipoIdentificacionActual VARCHAR2(10);
    numeroIdentificacionActual VARCHAR2(30);
    nombreClienteActual VARCHAR2(120);
    versionClienteActual NUMBER;
    fechaClienteActual TIMESTAMP;
    versionClienteRemoto NUMBER;
    rangoActual RANGO_FACTURA%ROWTYPE;
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM SYNC_RECIBIDO@' || pEnlace ||
        ' WHERE origenRecibido = ''CENTRAL'' AND idEnvioRecibido = :1'
        INTO cantidadRecibidos USING pIdSalida;
    IF cantidadRecibidos > 0 THEN
        UPDATE SYNC_SALIDA SET estadoSalida = 'APLICADO',
            fechaAplicacionSalida = SYSTIMESTAMP WHERE idSalida = pIdSalida;
        COMMIT;
        SP_REGISTRAR_BITACORA(pSucursal, 'BAJADA', pTabla, fechaInicio, 'OMITIDO');
        RETURN;
    END IF;

    SELECT RAWTOHEX(STANDARD_HASH(pTabla || '|' || pClave || '|' || pVersion, 'SHA256'))
    INTO huellaActual FROM DUAL;

    IF pTabla = 'PRODUCTO' THEN
        SELECT idProducto, codigoProducto, descripcionProducto,
               precioActualProducto, fechaModificacionProducto
        INTO idProductoActual, codigoProductoActual, descripcionProductoActual,
             precioActual, fechaProductoActual
        FROM PRODUCTO WHERE idProducto = TO_NUMBER(pClave);
        BEGIN
            EXECUTE IMMEDIATE 'SELECT fechaModificacionProducto FROM PRODUCTO@' || pEnlace ||
                ' WHERE idProducto = :1' INTO fechaProductoRemoto USING idProductoActual;
            IF fechaProductoActual > fechaProductoRemoto THEN
                EXECUTE IMMEDIATE 'UPDATE PRODUCTO@' || pEnlace ||
                    ' SET codigoProducto = :1, descripcionProducto = :2, precioActualProducto = :3, ' ||
                    'fechaModificacionProducto = :4 WHERE idProducto = :5'
                    USING codigoProductoActual, descripcionProductoActual,
                          precioActual, fechaProductoActual, idProductoActual;
            ELSE
                resultadoRecibidoActual := 'DESCARTADO';
            END IF;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            EXECUTE IMMEDIATE 'INSERT INTO PRODUCTO@' || pEnlace ||
                ' (idProducto, codigoProducto, descripcionProducto, precioActualProducto, ' ||
                'fechaModificacionProducto) VALUES (:1, :2, :3, :4, :5)'
                USING idProductoActual, codigoProductoActual, descripcionProductoActual,
                      precioActual, fechaProductoActual;
        END;

    ELSIF pTabla = 'CLIENTE' THEN
        idSucursalClienteActual := TO_NUMBER(SUBSTR(pClave, 1, INSTR(pClave, ':') - 1));
        idClienteLocalActual := TO_NUMBER(SUBSTR(pClave, INSTR(pClave, ':') + 1));
        IF idSucursalClienteActual = TO_NUMBER(SUBSTR(pSucursal, 4)) THEN
            resultadoRecibidoActual := 'DESCARTADO';
        ELSE
            SELECT tipoIdentificacionCliente, numeroIdentificacionCliente,
                   nombreCliente, versionCliente, fechaModificacionCliente
            INTO tipoIdentificacionActual, numeroIdentificacionActual,
                 nombreClienteActual, versionClienteActual, fechaClienteActual
            FROM CLIENTE WHERE idSucursalOrigen = idSucursalClienteActual
                           AND idClienteLocal = idClienteLocalActual;
            BEGIN
                EXECUTE IMMEDIATE 'SELECT versionCliente FROM CLIENTE@' || pEnlace ||
                    ' WHERE idSucursalOrigen = :1 AND idClienteLocal = :2'
                    INTO versionClienteRemoto
                    USING idSucursalClienteActual, idClienteLocalActual;
                IF versionClienteActual > versionClienteRemoto THEN
                    EXECUTE IMMEDIATE 'UPDATE CLIENTE@' || pEnlace ||
                        ' SET tipoIdentificacionCliente = :1, numeroIdentificacionCliente = :2, ' ||
                        'nombreCliente = :3, versionCliente = :4, fechaModificacionCliente = :5 ' ||
                        'WHERE idSucursalOrigen = :6 AND idClienteLocal = :7'
                        USING tipoIdentificacionActual, numeroIdentificacionActual,
                              nombreClienteActual, versionClienteActual, fechaClienteActual,
                              idSucursalClienteActual, idClienteLocalActual;
                ELSE
                    resultadoRecibidoActual := 'DESCARTADO';
                END IF;
            EXCEPTION WHEN NO_DATA_FOUND THEN
                EXECUTE IMMEDIATE 'INSERT INTO CLIENTE@' || pEnlace ||
                    ' (idSucursalOrigen, idClienteLocal, tipoIdentificacionCliente, ' ||
                    'numeroIdentificacionCliente, nombreCliente, versionCliente, ' ||
                    'fechaModificacionCliente) VALUES (:1, :2, :3, :4, :5, :6, :7)'
                    USING idSucursalClienteActual, idClienteLocalActual,
                          tipoIdentificacionActual, numeroIdentificacionActual,
                          nombreClienteActual, versionClienteActual, fechaClienteActual;
            END;
        END IF;

    ELSIF pTabla = 'RANGO_FACTURA' THEN
        SELECT * INTO rangoActual FROM RANGO_FACTURA
        WHERE idRango = TO_NUMBER(pClave);
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM RANGO_FACTURA@' || pEnlace ||
            ' WHERE idRango = :1' INTO cantidadRecibidos USING rangoActual.idRango;
        IF cantidadRecibidos = 0 THEN
            EXECUTE IMMEDIATE 'INSERT INTO RANGO_FACTURA@' || pEnlace ||
                ' (idRango, idSucursal, numeroInicialRango, numeroFinalRango, ' ||
                'proximoNumeroRango, estadoRango) VALUES (:1, :2, :3, :4, :5, :6)'
                USING rangoActual.idRango, rangoActual.idSucursal,
                      rangoActual.numeroInicialRango, rangoActual.numeroFinalRango,
                      rangoActual.proximoNumeroRango, rangoActual.estadoRango;
        ELSE
            resultadoRecibidoActual := 'DESCARTADO';
        END IF;
    ELSE
        RAISE_APPLICATION_ERROR(-20021, 'Tipo de bajada no reconocido: ' || pTabla);
    END IF;

    EXECUTE IMMEDIATE 'INSERT INTO SYNC_RECIBIDO@' || pEnlace ||
        ' (origenRecibido, idEnvioRecibido, huellaRecibido, ' ||
        'fechaRecepcionRecibido, resultadoRecibido) VALUES ' ||
        '(''CENTRAL'', :1, :2, SYSTIMESTAMP, :3)'
        USING pIdSalida, huellaActual, resultadoRecibidoActual;
    UPDATE SYNC_SALIDA SET estadoSalida = 'APLICADO',
        fechaAplicacionSalida = SYSTIMESTAMP WHERE idSalida = pIdSalida;
    COMMIT;
    SP_REGISTRAR_BITACORA(pSucursal, 'BAJADA', pTabla, fechaInicio,
                         CASE resultadoRecibidoActual WHEN 'APLICADO' THEN 'OK'
                              ELSE resultadoRecibidoActual END);
EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    SP_REGISTRAR_BITACORA(pSucursal, 'BAJADA', pTabla, fechaInicio, 'ERROR');
    RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_APLICAR_BAJADA

CREATE OR REPLACE PROCEDURE SP_CICLO_SYNC (pSucursal IN VARCHAR2) AS
    enlaceActual VARCHAR2(20);
    valorPrueba NUMBER;
    fechaInicio TIMESTAMP := SYSTIMESTAMP;
    cursorPendientes SYS_REFCURSOR;
    idSalidaActual NUMBER;
    tablaActual VARCHAR2(30);
    claveActual VARCHAR2(60);
    versionActual NUMBER;
BEGIN
    enlaceActual := CASE pSucursal
        WHEN 'SUC01' THEN 'LNK_SUC01'
        WHEN 'SUC02' THEN 'LNK_SUC02'
        ELSE NULL
    END;
    IF enlaceActual IS NULL THEN
        RAISE_APPLICATION_ERROR(-20022, 'Solo SUC01 y SUC02 usan enlace');
    END IF;

    BEGIN
        EXECUTE IMMEDIATE 'SELECT 1 FROM DUAL@' || enlaceActual INTO valorPrueba;
    EXCEPTION WHEN OTHERS THEN
        UPDATE SUCURSAL SET estadoConexionSucursal = 'SIN_CONEXION'
        WHERE codigoSucursal = pSucursal;
        COMMIT;
        SP_REGISTRAR_BITACORA(pSucursal, 'SUBIDA', 'SUCURSAL', fechaInicio, 'ERROR');
        RETURN;
    END;
    UPDATE SUCURSAL SET estadoConexionSucursal = 'CONECTADA'
    WHERE codigoSucursal = pSucursal;
    COMMIT;

    OPEN cursorPendientes FOR
        'SELECT idSalida, tablaOrigenSalida, claveRegistroSalida, versionSalida ' ||
        'FROM SYNC_SALIDA@' || enlaceActual ||
        ' WHERE destinoSalida = ''CENTRAL'' AND estadoSalida IN (''PENDIENTE'',''ENVIADO'') ' ||
        'ORDER BY idSalida';
    LOOP
        FETCH cursorPendientes INTO idSalidaActual, tablaActual, claveActual, versionActual;
        EXIT WHEN cursorPendientes%NOTFOUND;
        EXECUTE IMMEDIATE 'UPDATE SYNC_SALIDA@' || enlaceActual ||
            ' SET estadoSalida = ''ENVIADO'', fechaEnvioSalida = SYSTIMESTAMP ' ||
            'WHERE idSalida = :1 AND estadoSalida = ''PENDIENTE'''
            USING idSalidaActual;
        COMMIT;
        SP_APLICAR_SUBIDA(enlaceActual, pSucursal, idSalidaActual,
                         tablaActual, claveActual, versionActual);
    END LOOP;
    CLOSE cursorPendientes;

    FOR salidaActual IN (
        SELECT idSalida, tablaOrigenSalida, claveRegistroSalida, versionSalida
        FROM SYNC_SALIDA
        WHERE destinoSalida = pSucursal
          AND estadoSalida IN ('PENDIENTE', 'ENVIADO')
        ORDER BY idSalida
    ) LOOP
        UPDATE SYNC_SALIDA SET estadoSalida = 'ENVIADO',
            fechaEnvioSalida = SYSTIMESTAMP
        WHERE idSalida = salidaActual.idSalida AND estadoSalida = 'PENDIENTE';
        COMMIT;
        SP_APLICAR_BAJADA(enlaceActual, pSucursal, salidaActual.idSalida,
                         salidaActual.tablaOrigenSalida,
                         salidaActual.claveRegistroSalida, salidaActual.versionSalida);
    END LOOP;

    UPDATE SUCURSAL SET fechaUltimaSyncSucursal = SYSTIMESTAMP
    WHERE codigoSucursal = pSucursal;
    COMMIT;
EXCEPTION WHEN OTHERS THEN
    IF cursorPendientes%ISOPEN THEN CLOSE cursorPendientes; END IF;
    ROLLBACK;
    RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_CICLO_SYNC

CREATE OR REPLACE PROCEDURE SP_CAMBIAR_PRECIO (
    pIdProducto IN NUMBER,
    pPrecioNuevo IN NUMBER
) AS
BEGIN
    IF pPrecioNuevo < 0 THEN
        RAISE_APPLICATION_ERROR(-20023, 'El precio no puede ser negativo');
    END IF;
    UPDATE PRODUCTO SET precioActualProducto = pPrecioNuevo,
        fechaModificacionProducto = SYSTIMESTAMP
    WHERE idProducto = pIdProducto;
    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20024, 'Producto no encontrado');
    END IF;
    INSERT INTO SYNC_SALIDA (
        tablaOrigenSalida, claveRegistroSalida, destinoSalida,
        versionSalida, estadoSalida, fechaCreacionSalida
    )
    SELECT 'PRODUCTO', TO_CHAR(pIdProducto), codigoSucursal,
           1, 'PENDIENTE', SYSTIMESTAMP FROM SUCURSAL;
    COMMIT;
EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_CAMBIAR_PRECIO

-- A demanda, conectado a CENTRAL:
-- EXEC SP_CICLO_SYNC('SUC01');
-- EXEC SP_CICLO_SYNC('SUC02');
-- Para cambiar un precio y dejarlo pendiente para las tres sucursales:
-- EXEC SP_CAMBIAR_PRECIO(1, 455000);
