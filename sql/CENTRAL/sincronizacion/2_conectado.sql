-- CENTRAL. Sincronizacion con SUC01 y SUC02 (modo conectado). Se ejecuta despues de 1_motor.sql.

-- ciclo completo con una sucursal conectada: primero sube lo suyo y despues baja lo de la central
CREATE OR REPLACE PROCEDURE SP_CICLO_SYNC (pSucursal IN VARCHAR2) AS
    vEnlace VARCHAR2(20) := 'LNK_' || pSucursal;
    vPendientes SYS_REFCURSOR;
    vDireccion VARCHAR2(10) := 'SUBIDA';
    vPrueba NUMBER;
    vInicio DATE;
    vId NUMBER;
    vTabla VARCHAR2(30);
    vClave VARCHAR2(60);
    vVersion NUMBER;
    vDatos VARCHAR2(4000);
    vResultado VARCHAR2(10);
BEGIN
    -- si el enlace no responde se anota y se termina
    BEGIN
        EXECUTE IMMEDIATE 'SELECT 1 FROM DUAL@' || vEnlace INTO vPrueba;
    EXCEPTION WHEN OTHERS THEN
        UPDATE SUCURSAL SET estadoConexionSucursal = 'SIN_CONEXION' WHERE codigoSucursal = pSucursal;
        COMMIT;
        SP_REGISTRAR_BITACORA(pSucursal, 'SUBIDA', 'SUCURSAL', SYSDATE, 'ERROR');
        RETURN;
    END;
    UPDATE SUCURSAL SET estadoConexionSucursal = 'CONECTADA' WHERE codigoSucursal = pSucursal;

    -- subida: la sucursal manda lo que tiene pendiente
    vDireccion := 'SUBIDA';
    OPEN vPendientes FOR 'SELECT idSalida, tablaOrigenSalida, claveRegistroSalida, versionSalida FROM SYNC_SALIDA@' || vEnlace ||
        ' WHERE destinoSalida = ''CENTRAL'' AND estadoSalida <> ''APLICADO'' ORDER BY idSalida';
    LOOP
        FETCH vPendientes INTO vId, vTabla, vClave, vVersion;
        EXIT WHEN vPendientes%NOTFOUND;
        vInicio := SYSDATE;
        -- el registro se serializa en la sucursal y se aplica aqui
        EXECUTE IMMEDIATE 'SELECT FN_SERIALIZAR@' || vEnlace || '(:1, :2, ''CENTRAL'') FROM DUAL' INTO vDatos USING vTabla, vClave;
        SP_APLICAR_ENVIO(pSucursal, vId, vTabla, vClave, vVersion, vDatos, vResultado);
        EXECUTE IMMEDIATE 'UPDATE SYNC_SALIDA@' || vEnlace || ' SET estadoSalida = ''APLICADO'', fechaAplicacionSalida = SYSDATE WHERE idSalida = :1' USING vId;
        COMMIT;
        SP_REGISTRAR_BITACORA(pSucursal, vDireccion, vTabla, vInicio, CASE vResultado WHEN 'APLICADO' THEN 'OK' ELSE vResultado END);
    END LOOP;
    CLOSE vPendientes;

    -- bajada: la central manda lo que tiene pendiente para esta sucursal
    vDireccion := 'BAJADA';
    FOR e IN (SELECT idSalida, tablaOrigenSalida, claveRegistroSalida, versionSalida FROM SYNC_SALIDA
              WHERE destinoSalida = pSucursal AND estadoSalida <> 'APLICADO' ORDER BY idSalida) LOOP
        vInicio := SYSDATE;
        vTabla := e.tablaOrigenSalida;
        vDatos := FN_SERIALIZAR(e.tablaOrigenSalida, e.claveRegistroSalida, pSucursal);
        -- el mismo procedimiento se ejecuta en la sucursal a traves del enlace
        EXECUTE IMMEDIATE 'BEGIN SP_APLICAR_ENVIO@' || vEnlace || '(''CENTRAL'', :1, :2, :3, :4, :5, :6); END;'
            USING e.idSalida, e.tablaOrigenSalida, e.claveRegistroSalida, e.versionSalida, vDatos, OUT vResultado;
        UPDATE SYNC_SALIDA SET estadoSalida = 'APLICADO', fechaAplicacionSalida = SYSDATE WHERE idSalida = e.idSalida;
        COMMIT;
        SP_REGISTRAR_BITACORA(pSucursal, vDireccion, vTabla, vInicio, CASE vResultado WHEN 'APLICADO' THEN 'OK' ELSE vResultado END);
    END LOOP;

    UPDATE SUCURSAL SET fechaUltimaSyncSucursal = SYSDATE WHERE codigoSucursal = pSucursal;
    COMMIT;
EXCEPTION WHEN OTHERS THEN
    IF vPendientes%ISOPEN THEN
        CLOSE vPendientes;
    END IF;
    ROLLBACK;
    SP_REGISTRAR_BITACORA(pSucursal, vDireccion, NVL(vTabla, 'CICLO'), SYSDATE, 'ERROR');
    RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_CICLO_SYNC

-- cambia el precio en la central y lo deja pendiente para todas las sucursales
CREATE OR REPLACE PROCEDURE SP_CAMBIAR_PRECIO (pIdProducto IN NUMBER, pPrecio IN NUMBER) AS
BEGIN
    UPDATE PRODUCTO SET precioActualProducto = pPrecio, fechaModificacionProducto = SYSDATE WHERE idProducto = pIdProducto;
    IF SQL%ROWCOUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'El producto no existe');
    END IF;
    FOR s IN (SELECT codigoSucursal FROM SUCURSAL) LOOP
        SP_NUEVO_ENVIO('PRODUCTO', pIdProducto, s.codigoSucursal, 1);
    END LOOP;
    COMMIT;
EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_CAMBIAR_PRECIO
