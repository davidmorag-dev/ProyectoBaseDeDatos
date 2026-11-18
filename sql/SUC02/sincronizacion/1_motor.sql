-- SUC02. Motor comun de la sincronizacion. Es el mismo codigo en los cuatro nodos.
-- Se ejecuta despues de 1_instalar.sql.

------------------------------------------------------------
-- 1. FN_CAMPO: devuelve el campo numero N de un texto separado por un simbolo
------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_CAMPO (pTexto IN VARCHAR2, pSep IN VARCHAR2, pN IN NUMBER) RETURN VARCHAR2 AS
BEGIN
    RETURN REGEXP_SUBSTR(pTexto, '([^' || pSep || ']*)(' || pSep || '|$)', 1, pN, NULL, 1);
END;
/

------------------------------------------------------------
-- 2. FN_HUELLA: huella SHA-256 de un texto
------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_HUELLA (pTexto IN VARCHAR2) RETURN VARCHAR2 AS
    vHuella VARCHAR2(64);
BEGIN
    SELECT RAWTOHEX(STANDARD_HASH(pTexto, 'SHA256')) INTO vHuella FROM DUAL;
    RETURN vHuella;
END;
/

------------------------------------------------------------
-- 3. SP_REGISTRAR_BITACORA: anota una sincronizacion en la bitacora
------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_REGISTRAR_BITACORA (
    pContraparte IN VARCHAR2, pDireccion IN VARCHAR2, pTabla IN VARCHAR2, pInicio IN DATE, pResultado IN VARCHAR2
) AS
BEGIN
    INSERT INTO BITACORA_SYNC (contraparteBitacora, direccionBitacora, tablaAfectadaBitacora, fechaInicioBitacora, fechaFinBitacora, resultadoBitacora)
    VALUES (pContraparte, pDireccion, pTabla, pInicio, SYSDATE, pResultado);
    COMMIT;
END;
/

------------------------------------------------------------
-- 4. SP_NUEVO_ENVIO: deja un envio pendiente para que lo recoja la sincronizacion
------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_NUEVO_ENVIO (pTabla IN VARCHAR2, pClave IN VARCHAR2, pDestino IN VARCHAR2, pVersion IN NUMBER) AS
BEGIN
    INSERT INTO SYNC_SALIDA (tablaOrigenSalida, claveRegistroSalida, destinoSalida, versionSalida, estadoSalida, fechaCreacionSalida)
    VALUES (pTabla, pClave, pDestino, pVersion, 'PENDIENTE', SYSDATE);
END;
/

------------------------------------------------------------
-- 5. FN_SERIALIZAR: convierte un registro en texto (campos con ~ y lineas de factura con #)
------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_SERIALIZAR (pTabla IN VARCHAR2, pClave IN VARCHAR2, pDestino IN VARCHAR2) RETURN VARCHAR2 AS
    vDatos VARCHAR2(4000);
BEGIN
    IF pTabla = 'PRODUCTO' THEN
        SELECT descripcionProducto || '~' || TO_CHAR(precioActualProducto, 'FM999999999990.00') || '~' ||
            TO_CHAR(fechaModificacionProducto, 'YYYY-MM-DD HH24:MI:SS')
        INTO vDatos FROM PRODUCTO WHERE idProducto = TO_NUMBER(pClave);
    ELSIF pTabla = 'CLIENTE' THEN
        SELECT tipoIdentificacionCliente || '~' || numeroIdentificacionCliente || '~' || nombreCliente || '~' ||
            versionCliente || '~' || TO_CHAR(fechaModificacionCliente, 'YYYY-MM-DD HH24:MI:SS')
        INTO vDatos FROM CLIENTE
        WHERE idSucursalOrigen = TO_NUMBER(FN_CAMPO(pClave, ':', 1)) AND idClienteLocal = TO_NUMBER(FN_CAMPO(pClave, ':', 2));
    ELSIF pTabla = 'FACTURA' THEN
        SELECT idSucursalEmisora || '~' || idSucursalCliente || '~' || idClienteLocal || '~' ||
            TO_CHAR(fechaEmisionFactura, 'YYYY-MM-DD HH24:MI:SS') || '~' || TO_CHAR(totalFactura, 'FM999999999990.00')
        INTO vDatos FROM FACTURA WHERE idFactura = TO_NUMBER(pClave);
        FOR d IN (SELECT * FROM DETALLE_FACTURA WHERE idFactura = TO_NUMBER(pClave) ORDER BY lineaDetalle) LOOP
            vDatos := vDatos || '#' || d.lineaDetalle || '~' || d.idProducto || '~' ||
                TO_CHAR(d.cantidadDetalle, 'FM999999999990.00') || '~' || TO_CHAR(d.precioUnitarioDetalle, 'FM999999999990.00');
        END LOOP;
    ELSIF pTabla = 'RANGO_FACTURA' AND pDestino <> 'CENTRAL' THEN
        SELECT idSucursal || '~' || numeroInicialRango || '~' || numeroFinalRango || '~' || proximoNumeroRango || '~' || estadoRango
        INTO vDatos FROM RANGO_FACTURA WHERE idRango = TO_NUMBER(pClave);
    ELSE
        -- la solicitud de un bloque nuevo no lleva datos
        vDatos := '-';
    END IF;
    RETURN vDatos;
END;
/

------------------------------------------------------------
-- 6. SP_APLICAR_ENVIO: aplica un envio en este nodo. Sirve para los dos modos (enlace o archivo)
-- pOrigen es el nodo que lo manda. pResultado: APLICADO, DESCARTADO u OMITIDO (ya se habia recibido)
------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_APLICAR_ENVIO (
    pOrigen IN VARCHAR2, pIdEnvio IN NUMBER, pTabla IN VARCHAR2, pClave IN VARCHAR2,
    pVersion IN NUMBER, pDatos IN VARCHAR2, pResultado OUT VARCHAR2
) AS
    vRepetido NUMBER;
    vSuc NUMBER;
    vLocal NUMBER;
    vFecha DATE;
    vLinea VARCHAR2(200);
    i NUMBER;
BEGIN
    -- un envio que ya llego no se aplica otra vez
    SELECT COUNT(*) INTO vRepetido FROM SYNC_RECIBIDO WHERE origenRecibido = pOrigen AND idEnvioRecibido = pIdEnvio;
    IF vRepetido > 0 THEN
        pResultado := 'OMITIDO';
        RETURN;
    END IF;
    pResultado := 'APLICADO';

    IF pTabla = 'PRODUCTO' THEN
        -- gana el cambio mas reciente
        vFecha := TO_DATE(FN_CAMPO(pDatos, '~', 3), 'YYYY-MM-DD HH24:MI:SS');
        MERGE INTO PRODUCTO p USING DUAL ON (p.idProducto = TO_NUMBER(pClave))
        WHEN MATCHED THEN UPDATE SET descripcionProducto = FN_CAMPO(pDatos, '~', 1),
            precioActualProducto = TO_NUMBER(FN_CAMPO(pDatos, '~', 2), '999999999990.00'), fechaModificacionProducto = vFecha
            WHERE p.fechaModificacionProducto < vFecha
        WHEN NOT MATCHED THEN INSERT VALUES (TO_NUMBER(pClave), FN_CAMPO(pDatos, '~', 1),
            TO_NUMBER(FN_CAMPO(pDatos, '~', 2), '999999999990.00'), vFecha);
        IF SQL%ROWCOUNT = 0 THEN
            pResultado := 'DESCARTADO';
        END IF;

    ELSIF pTabla = 'CLIENTE' THEN
        vSuc := TO_NUMBER(FN_CAMPO(pClave, ':', 1));
        vLocal := TO_NUMBER(FN_CAMPO(pClave, ':', 2));
        vFecha := TO_DATE(FN_CAMPO(pDatos, '~', 5), 'YYYY-MM-DD HH24:MI:SS');
        -- solo se aplica si la version es mayor. Asi el cliente que vuelve a su sucursal de origen no se altera
        MERGE INTO CLIENTE c USING DUAL ON (c.idSucursalOrigen = vSuc AND c.idClienteLocal = vLocal)
        WHEN MATCHED THEN UPDATE SET tipoIdentificacionCliente = FN_CAMPO(pDatos, '~', 1),
            numeroIdentificacionCliente = FN_CAMPO(pDatos, '~', 2), nombreCliente = FN_CAMPO(pDatos, '~', 3),
            versionCliente = pVersion, fechaModificacionCliente = vFecha
            WHERE c.versionCliente < pVersion
        WHEN NOT MATCHED THEN INSERT VALUES (vSuc, vLocal, FN_CAMPO(pDatos, '~', 1), FN_CAMPO(pDatos, '~', 2),
            FN_CAMPO(pDatos, '~', 3), pVersion, vFecha);
        IF SQL%ROWCOUNT = 0 THEN
            pResultado := 'DESCARTADO';
        ELSIF pOrigen <> 'CENTRAL' THEN
            -- solo la central reparte y consolida los clientes
            EXECUTE IMMEDIATE 'BEGIN SP_CONSOLIDAR_CLIENTE(:1, :2); END;' USING vSuc, vLocal;
        END IF;

    ELSIF pTabla = 'FACTURA' THEN
        vLinea := FN_CAMPO(pDatos, '#', 1);
        INSERT INTO FACTURA VALUES (TO_NUMBER(pClave), TO_NUMBER(FN_CAMPO(vLinea, '~', 1)), TO_NUMBER(FN_CAMPO(vLinea, '~', 2)),
            TO_NUMBER(FN_CAMPO(vLinea, '~', 3)), TO_DATE(FN_CAMPO(vLinea, '~', 4), 'YYYY-MM-DD HH24:MI:SS'),
            TO_NUMBER(FN_CAMPO(vLinea, '~', 5), '999999999990.00'));
        i := 2;
        LOOP
            vLinea := FN_CAMPO(pDatos, '#', i);
            EXIT WHEN vLinea IS NULL;
            INSERT INTO DETALLE_FACTURA VALUES (TO_NUMBER(pClave), TO_NUMBER(FN_CAMPO(vLinea, '~', 1)),
                TO_NUMBER(FN_CAMPO(vLinea, '~', 2)), TO_NUMBER(FN_CAMPO(vLinea, '~', 3), '999999999990.00'),
                TO_NUMBER(FN_CAMPO(vLinea, '~', 4), '999999999990.00'));
            i := i + 1;
        END LOOP;

    ELSIF pTabla = 'RANGO_FACTURA' THEN
        IF pOrigen = 'CENTRAL' THEN
            -- la central entrego un bloque
            INSERT INTO RANGO_FACTURA VALUES (TO_NUMBER(pClave), TO_NUMBER(FN_CAMPO(pDatos, '~', 1)),
                TO_NUMBER(FN_CAMPO(pDatos, '~', 2)), TO_NUMBER(FN_CAMPO(pDatos, '~', 3)),
                TO_NUMBER(FN_CAMPO(pDatos, '~', 4)), FN_CAMPO(pDatos, '~', 5));
        ELSE
            -- la sucursal pidio un bloque, solo la central lo asigna
            EXECUTE IMMEDIATE 'BEGIN SP_ASIGNAR_BLOQUE(:1); END;' USING pOrigen;
        END IF;
    ELSE
        RAISE_APPLICATION_ERROR(-20001, 'Tipo de envio desconocido: ' || pTabla);
    END IF;

    INSERT INTO SYNC_RECIBIDO (origenRecibido, idEnvioRecibido, huellaRecibido, fechaRecepcionRecibido, resultadoRecibido)
    VALUES (pOrigen, pIdEnvio, FN_HUELLA(pDatos), SYSDATE, pResultado);
END;
/


-- errores de compilacion de este archivo (si no sale nada, todo bien)
SELECT name, line, text FROM user_errors ORDER BY name, sequence;
