-- CENTRAL. Sincronizacion con las sucursales. Se ejecuta despues de 1_instalar.sql.
-- Antes de la parte B, como SYSTEM en XEPDB1:
--   CREATE DIRECTORY DIR_SYNC AS 'C:\sync';
--   GRANT READ, WRITE ON DIRECTORY DIR_SYNC TO CENTRAL;
--   GRANT CREATE JOB TO CENTRAL;
-- La parte C necesita que SUC01 y SUC02 sean alcanzables por la red; ejecutarla al final.

-- PARTE A. SINCRONIZACION CONECTADA (SUC01 y SUC02)

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

-- Reparte el cliente y registra si esta repetido
CREATE OR REPLACE PROCEDURE SP_CONSOLIDAR_CLIENTE (
    pClave IN VARCHAR2,
    pVersion IN NUMBER,
    pTipoIdentificacion IN VARCHAR2,
    pNumeroIdentificacion IN VARCHAR2,
    pIdSucursalCliente IN NUMBER,
    pIdClienteLocal IN NUMBER
) AS
    idSucursalCanonicaActual NUMBER;
    idClienteCanonicoActual NUMBER;
BEGIN
    INSERT INTO SYNC_SALIDA (
        tablaOrigenSalida, claveRegistroSalida, destinoSalida,
        versionSalida, estadoSalida, fechaCreacionSalida
    )
    SELECT 'CLIENTE', pClave, codigoSucursal,
           pVersion, 'PENDIENTE', SYSDATE
    FROM SUCURSAL;

    BEGIN
        SELECT equivalencia.idSucursalCanonica, equivalencia.idClienteCanonico
        INTO idSucursalCanonicaActual, idClienteCanonicoActual
        FROM CLIENTE_EQUIVALENCIA equivalencia
        JOIN CLIENTE cliente
          ON cliente.idSucursalOrigen = equivalencia.idSucursalOrigen
         AND cliente.idClienteLocal = equivalencia.idClienteLocal
        WHERE cliente.tipoIdentificacionCliente = pTipoIdentificacion
          AND cliente.numeroIdentificacionCliente = pNumeroIdentificacion
          AND ROWNUM = 1;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        SELECT idSucursalOrigen, idClienteLocal
        INTO idSucursalCanonicaActual, idClienteCanonicoActual
        FROM (
            SELECT idSucursalOrigen, idClienteLocal
            FROM CLIENTE
            WHERE tipoIdentificacionCliente = pTipoIdentificacion
              AND numeroIdentificacionCliente = pNumeroIdentificacion
            ORDER BY CASE WHEN idSucursalOrigen = pIdSucursalCliente
                           AND idClienteLocal = pIdClienteLocal
                          THEN 1 ELSE 0 END,
                     fechaModificacionCliente, idSucursalOrigen, idClienteLocal
        ) WHERE ROWNUM = 1;
    END;

    FOR clienteDuplicado IN (
        SELECT idSucursalOrigen, idClienteLocal FROM CLIENTE
        WHERE tipoIdentificacionCliente = pTipoIdentificacion
          AND numeroIdentificacionCliente = pNumeroIdentificacion
          AND (idSucursalOrigen <> idSucursalCanonicaActual
               OR idClienteLocal <> idClienteCanonicoActual)
    ) LOOP
        MERGE INTO CLIENTE_EQUIVALENCIA equivalencia
        USING DUAL ON (
            equivalencia.idSucursalOrigen = clienteDuplicado.idSucursalOrigen
            AND equivalencia.idClienteLocal = clienteDuplicado.idClienteLocal
        )
        WHEN NOT MATCHED THEN INSERT (
            idSucursalOrigen, idClienteLocal, idSucursalCanonica,
            idClienteCanonico, fechaDeteccionEquivalencia
        ) VALUES (
            clienteDuplicado.idSucursalOrigen, clienteDuplicado.idClienteLocal,
            idSucursalCanonicaActual, idClienteCanonicoActual, SYSDATE
        );
    END LOOP;
END;
/
SHOW ERRORS PROCEDURE SP_CONSOLIDAR_CLIENTE

-- Asigna el siguiente bloque de facturas
CREATE OR REPLACE PROCEDURE SP_ASIGNAR_BLOQUE (
    pSucursal IN VARCHAR2
) AS
    idRangoNuevo NUMBER;
    numeroInicialNuevo NUMBER;
BEGIN
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
        1, 'PENDIENTE', SYSDATE
    );
END;
/
SHOW ERRORS PROCEDURE SP_ASIGNAR_BLOQUE

CREATE OR REPLACE PROCEDURE SP_APLICAR_SUBIDA (
    pEnlace IN VARCHAR2,
    pSucursal IN VARCHAR2,
    pIdSalida IN NUMBER,
    pTabla IN VARCHAR2,
    pClave IN VARCHAR2,
    pVersion IN NUMBER
) AS
    fechaInicio DATE := SYSDATE;
    cantidadRecibidos NUMBER;
    resultadoRecibidoActual VARCHAR2(10) := 'APLICADO';
    huellaActual VARCHAR2(64);
    idSucursalClienteActual NUMBER;
    idClienteLocalActual NUMBER;
    tipoIdentificacionActual VARCHAR2(10);
    numeroIdentificacionActual VARCHAR2(30);
    nombreClienteActual VARCHAR2(120);
    versionClienteActual NUMBER;
    fechaModificacionActual DATE;
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
            ' SET estadoSalida = ''APLICADO'', fechaAplicacionSalida = SYSDATE WHERE idSalida = :1'
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
            SP_CONSOLIDAR_CLIENTE(pClave, versionClienteActual, tipoIdentificacionActual,
                numeroIdentificacionActual, idSucursalClienteActual, idClienteLocalActual);
        END IF;

    ELSIF pTabla = 'FACTURA' THEN
        EXECUTE IMMEDIATE 'INSERT INTO FACTURA SELECT * FROM FACTURA@' || pEnlace ||
            ' WHERE idFactura = :1' USING TO_NUMBER(pClave);
        EXECUTE IMMEDIATE 'INSERT INTO DETALLE_FACTURA SELECT * FROM DETALLE_FACTURA@' || pEnlace ||
            ' WHERE idFactura = :1' USING TO_NUMBER(pClave);

    ELSIF pTabla = 'RANGO_FACTURA' THEN
        SP_ASIGNAR_BLOQUE(pSucursal);
    ELSE
        RAISE_APPLICATION_ERROR(-20020, 'Tipo de subida no reconocido: ' || pTabla);
    END IF;

    INSERT INTO SYNC_RECIBIDO (
        origenRecibido, idEnvioRecibido, huellaRecibido,
        fechaRecepcionRecibido, resultadoRecibido
    ) VALUES (
        pSucursal, pIdSalida, huellaActual, SYSDATE, resultadoRecibidoActual
    );
    EXECUTE IMMEDIATE 'UPDATE SYNC_SALIDA@' || pEnlace ||
        ' SET estadoSalida = ''APLICADO'', fechaAplicacionSalida = SYSDATE WHERE idSalida = :1'
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
    fechaInicio DATE := SYSDATE;
    cantidadRecibidos NUMBER;
    resultadoRecibidoActual VARCHAR2(10) := 'APLICADO';
    huellaActual VARCHAR2(64);
    idProductoActual NUMBER;
    descripcionProductoActual VARCHAR2(200);
    precioActual NUMBER(12,2);
    fechaProductoActual DATE;
    fechaProductoRemoto DATE;
    idSucursalClienteActual NUMBER;
    idClienteLocalActual NUMBER;
    tipoIdentificacionActual VARCHAR2(10);
    numeroIdentificacionActual VARCHAR2(30);
    nombreClienteActual VARCHAR2(120);
    versionClienteActual NUMBER;
    fechaClienteActual DATE;
    versionClienteRemoto NUMBER;
    rangoActual RANGO_FACTURA%ROWTYPE;
BEGIN
    EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM SYNC_RECIBIDO@' || pEnlace ||
        ' WHERE origenRecibido = ''CENTRAL'' AND idEnvioRecibido = :1'
        INTO cantidadRecibidos USING pIdSalida;
    IF cantidadRecibidos > 0 THEN
        UPDATE SYNC_SALIDA SET estadoSalida = 'APLICADO',
            fechaAplicacionSalida = SYSDATE WHERE idSalida = pIdSalida;
        COMMIT;
        SP_REGISTRAR_BITACORA(pSucursal, 'BAJADA', pTabla, fechaInicio, 'OMITIDO');
        RETURN;
    END IF;

    SELECT RAWTOHEX(STANDARD_HASH(pTabla || '|' || pClave || '|' || pVersion, 'SHA256'))
    INTO huellaActual FROM DUAL;

    IF pTabla = 'PRODUCTO' THEN
        SELECT idProducto, descripcionProducto,
               precioActualProducto, fechaModificacionProducto
        INTO idProductoActual, descripcionProductoActual,
             precioActual, fechaProductoActual
        FROM PRODUCTO WHERE idProducto = TO_NUMBER(pClave);
        BEGIN
            EXECUTE IMMEDIATE 'SELECT fechaModificacionProducto FROM PRODUCTO@' || pEnlace ||
                ' WHERE idProducto = :1' INTO fechaProductoRemoto USING idProductoActual;
            IF fechaProductoActual > fechaProductoRemoto THEN
                EXECUTE IMMEDIATE 'UPDATE PRODUCTO@' || pEnlace ||
                    ' SET descripcionProducto = :1, precioActualProducto = :2, ' ||
                    'fechaModificacionProducto = :3 WHERE idProducto = :4'
                    USING descripcionProductoActual,
                          precioActual, fechaProductoActual, idProductoActual;
            ELSE
                resultadoRecibidoActual := 'DESCARTADO';
            END IF;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            EXECUTE IMMEDIATE 'INSERT INTO PRODUCTO@' || pEnlace ||
                ' (idProducto, descripcionProducto, precioActualProducto, ' ||
                'fechaModificacionProducto) VALUES (:1, :2, :3, :4)'
                USING idProductoActual, descripcionProductoActual,
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
        '(''CENTRAL'', :1, :2, SYSDATE, :3)'
        USING pIdSalida, huellaActual, resultadoRecibidoActual;
    UPDATE SYNC_SALIDA SET estadoSalida = 'APLICADO',
        fechaAplicacionSalida = SYSDATE WHERE idSalida = pIdSalida;
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
    fechaInicio DATE := SYSDATE;
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
            ' SET estadoSalida = ''ENVIADO'', fechaEnvioSalida = SYSDATE ' ||
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
            fechaEnvioSalida = SYSDATE
        WHERE idSalida = salidaActual.idSalida AND estadoSalida = 'PENDIENTE';
        COMMIT;
        SP_APLICAR_BAJADA(enlaceActual, pSucursal, salidaActual.idSalida,
                         salidaActual.tablaOrigenSalida,
                         salidaActual.claveRegistroSalida, salidaActual.versionSalida);
    END LOOP;

    UPDATE SUCURSAL SET fechaUltimaSyncSucursal = SYSDATE
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
        fechaModificacionProducto = SYSDATE
    WHERE idProducto = pIdProducto;
    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20024, 'Producto no encontrado');
    END IF;
    INSERT INTO SYNC_SALIDA (
        tablaOrigenSalida, claveRegistroSalida, destinoSalida,
        versionSalida, estadoSalida, fechaCreacionSalida
    )
    SELECT 'PRODUCTO', TO_CHAR(pIdProducto), codigoSucursal,
           1, 'PENDIENTE', SYSDATE FROM SUCURSAL;
    COMMIT;
EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_CAMBIAR_PRECIO

-- EXEC SP_CICLO_SYNC('SUC01');
-- EXEC SP_CICLO_SYNC('SUC02');
-- EXEC SP_CAMBIAR_PRECIO(1, 455000);

-- PARTE B. SINCRONIZACION POR CORREO (SUC03): RECIBIR EL LOTE

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

-- Lee el lote de una sucursal y lo aplica
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

    -- Validar el lote
    IF cantidadLineas = 0 OR FN_CAMPO(lineas(1), '\|', 1) <> 'ENC'
       OR FN_CAMPO(lineas(1), '\|', 2) <> pOrigen THEN
        RAISE_APPLICATION_ERROR(-20040, 'Encabezado del lote invalido');
    END IF;
    FOR i IN 2 .. cantidadLineas LOOP
        IF FN_CAMPO(lineas(i), '\|', 1) = 'ENV' THEN
            cantidadEnvios := cantidadEnvios + 1;
            IF FN_HUELLA(FN_CAMPO(lineas(i), '\|', 6)) <> FN_CAMPO(lineas(i), '\|', 7) THEN
                RAISE_APPLICATION_ERROR(-20041, 'Huella distinta en el envio ' ||
                                        FN_CAMPO(lineas(i), '\|', 2));
            END IF;
        END IF;
    END LOOP;
    IF cantidadEnvios <> TO_NUMBER(FN_CAMPO(lineas(1), '\|', 5)) THEN
        RAISE_APPLICATION_ERROR(-20042, 'El lote llego incompleto');
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

-- EXEC SP_PROCESAR_LOTE('lote_SUC03_0001.txt', 'SUC03');

-- PARTE B2. SINCRONIZACION POR CORREO (SUC03): GENERAR LA RESPUESTA

CREATE OR REPLACE FUNCTION FN_SERIALIZAR (
    pTabla IN VARCHAR2,
    pClave IN VARCHAR2
) RETURN VARCHAR2 AS
    datosActuales VARCHAR2(4000);
BEGIN
    IF pTabla = 'PRODUCTO' THEN
        SELECT descripcionProducto || '~' ||
               TO_CHAR(precioActualProducto, 'FM999999999990.00') || '~' ||
               TO_CHAR(fechaModificacionProducto, 'YYYY-MM-DD HH24:MI:SS')
        INTO datosActuales
        FROM PRODUCTO WHERE idProducto = TO_NUMBER(pClave);
    ELSIF pTabla = 'CLIENTE' THEN
        SELECT tipoIdentificacionCliente || '~' || numeroIdentificacionCliente || '~' ||
               nombreCliente || '~' || versionCliente || '~' ||
               TO_CHAR(fechaModificacionCliente, 'YYYY-MM-DD HH24:MI:SS')
        INTO datosActuales
        FROM CLIENTE
        WHERE idSucursalOrigen = TO_NUMBER(SUBSTR(pClave, 1, INSTR(pClave, ':') - 1))
          AND idClienteLocal = TO_NUMBER(SUBSTR(pClave, INSTR(pClave, ':') + 1));
    ELSIF pTabla = 'RANGO_FACTURA' THEN
        SELECT idSucursal || '~' || numeroInicialRango || '~' || numeroFinalRango || '~' ||
               proximoNumeroRango || '~' || estadoRango
        INTO datosActuales
        FROM RANGO_FACTURA WHERE idRango = TO_NUMBER(pClave);
    ELSE
        RAISE_APPLICATION_ERROR(-20050, 'Tipo de envio no reconocido: ' || pTabla);
    END IF;
    RETURN datosActuales;
END;
/
SHOW ERRORS FUNCTION FN_SERIALIZAR

-- Numero de la proxima respuesta
CREATE OR REPLACE FUNCTION FN_SIGUIENTE_RESPUESTA (
    pDestino IN VARCHAR2
) RETURN NUMBER AS
    numeroRespuesta NUMBER;
BEGIN
    SELECT COUNT(*) + 1 INTO numeroRespuesta FROM BITACORA_SYNC
    WHERE contraparteBitacora = pDestino
      AND direccionBitacora = 'LOTE_GEN' AND resultadoBitacora = 'OK';
    RETURN numeroRespuesta;
END;
/
SHOW ERRORS FUNCTION FN_SIGUIENTE_RESPUESTA

-- Escribe la respuesta para la sucursal
CREATE OR REPLACE PROCEDURE SP_GENERAR_RESPUESTA (
    pDestino IN VARCHAR2,
    pNumero IN NUMBER
) AS
    archivo UTL_FILE.FILE_TYPE;
    fechaInicio DATE := SYSDATE;
    idMaximo NUMBER;
    cantidadEnvios NUMBER;
    modoActual VARCHAR2(10);
    datosActuales VARCHAR2(4000);
BEGIN
    SELECT modoSyncSucursal INTO modoActual FROM SUCURSAL WHERE codigoSucursal = pDestino;
    IF modoActual <> 'DIFERIDO' THEN
        RAISE_APPLICATION_ERROR(-20051, 'Solo las sucursales en modo diferido reciben respuesta');
    END IF;

    SELECT NVL(MAX(idSalida), 0), COUNT(*) INTO idMaximo, cantidadEnvios
    FROM SYNC_SALIDA
    WHERE destinoSalida = pDestino AND estadoSalida IN ('PENDIENTE', 'ENVIADO');

    archivo := UTL_FILE.FOPEN('DIR_SYNC',
        'respuesta_' || pDestino || '_' || LPAD(pNumero, 4, '0') || '.txt', 'W', 32767);
    UTL_FILE.PUT_LINE(archivo, 'ENC|CENTRAL|' || pNumero || '|' ||
        TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') || '|' || cantidadEnvios || '|' || pDestino);

    FOR envio IN (
        SELECT idSalida, tablaOrigenSalida, claveRegistroSalida, versionSalida
        FROM SYNC_SALIDA
        WHERE destinoSalida = pDestino AND idSalida <= idMaximo
          AND estadoSalida IN ('PENDIENTE', 'ENVIADO')
        ORDER BY idSalida
    ) LOOP
        datosActuales := FN_SERIALIZAR(envio.tablaOrigenSalida, envio.claveRegistroSalida);
        UTL_FILE.PUT_LINE(archivo, 'ENV|' || envio.idSalida || '|' ||
            envio.tablaOrigenSalida || '|' || envio.claveRegistroSalida || '|' ||
            envio.versionSalida || '|' || datosActuales || '|' ||
            FN_HUELLA(datosActuales));
    END LOOP;

    -- Acuses
    FOR acuse IN (
        SELECT idEnvioRecibido FROM SYNC_RECIBIDO
        WHERE origenRecibido = pDestino ORDER BY idEnvioRecibido
    ) LOOP
        UTL_FILE.PUT_LINE(archivo, 'ACK|' || acuse.idEnvioRecibido);
    END LOOP;
    UTL_FILE.FCLOSE(archivo);

    UPDATE SYNC_SALIDA SET estadoSalida = 'ENVIADO', fechaEnvioSalida = SYSDATE
    WHERE destinoSalida = pDestino AND idSalida <= idMaximo
      AND estadoSalida IN ('PENDIENTE', 'ENVIADO');
    COMMIT;
    SP_REGISTRAR_BITACORA(pDestino, 'LOTE_GEN', 'LOTE', fechaInicio, 'OK');
EXCEPTION WHEN OTHERS THEN
    IF UTL_FILE.IS_OPEN(archivo) THEN UTL_FILE.FCLOSE(archivo); END IF;
    ROLLBACK;
    SP_REGISTRAR_BITACORA(pDestino, 'LOTE_GEN', 'LOTE', fechaInicio, 'ERROR');
    RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_GENERAR_RESPUESTA

-- Genera la respuesta todos los dias a las 9 p. m.
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'JOB_RESPUESTA_SUC03',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN SP_GENERAR_RESPUESTA(''SUC03'', FN_SIGUIENTE_RESPUESTA(''SUC03'')); END;',
        repeat_interval => 'FREQ=DAILY;BYHOUR=21;BYMINUTE=0;BYSECOND=0',
        enabled         => TRUE);
END;
/

-- EXEC SP_GENERAR_RESPUESTA('SUC03', FN_SIGUIENTE_RESPUESTA('SUC03'));

-- PARTE C. ENLACES HACIA SUC01 Y SUC02 (pide IP, usuario y clave)

SET VERIFY OFF
ACCEPT hostSuc01 CHAR PROMPT 'IP o nombre de SUC01: '
ACCEPT puertoSuc01 NUMBER DEFAULT 1521 PROMPT 'Puerto de SUC01 [1521]: '
ACCEPT servicioSuc01 CHAR DEFAULT XEPDB1 PROMPT 'Servicio de SUC01 [XEPDB1]: '
ACCEPT usuarioSuc01 CHAR PROMPT 'Usuario Oracle de SUC01: '
ACCEPT claveSuc01 CHAR PROMPT 'Clave Oracle de SUC01: ' HIDE

CREATE DATABASE LINK LNK_SUC01
CONNECT TO &usuarioSuc01 IDENTIFIED BY "&claveSuc01"
USING '//&hostSuc01:&puertoSuc01/&servicioSuc01';

ACCEPT hostSuc02 CHAR PROMPT 'IP o nombre de SUC02: '
ACCEPT puertoSuc02 NUMBER DEFAULT 1521 PROMPT 'Puerto de SUC02 [1521]: '
ACCEPT servicioSuc02 CHAR DEFAULT XEPDB1 PROMPT 'Servicio de SUC02 [XEPDB1]: '
ACCEPT usuarioSuc02 CHAR PROMPT 'Usuario Oracle de SUC02: '
ACCEPT claveSuc02 CHAR PROMPT 'Clave Oracle de SUC02: ' HIDE

CREATE DATABASE LINK LNK_SUC02
CONNECT TO &usuarioSuc02 IDENTIFIED BY "&claveSuc02"
USING '//&hostSuc02:&puertoSuc02/&servicioSuc02';

SELECT 'SUC01' AS sucursal, COUNT(*) AS sucursales FROM SUCURSAL@LNK_SUC01
UNION ALL
SELECT 'SUC02', COUNT(*) FROM SUCURSAL@LNK_SUC02;

UNDEFINE hostSuc01 puertoSuc01 servicioSuc01 usuarioSuc01 claveSuc01
UNDEFINE hostSuc02 puertoSuc02 servicioSuc02 usuarioSuc02 claveSuc02
