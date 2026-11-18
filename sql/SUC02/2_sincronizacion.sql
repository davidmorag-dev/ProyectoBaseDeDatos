-- SUC02. Sincronizacion: lo que genera los envios hacia la central. Se ejecuta despues de 1_instalar.sql.
-- Cada factura o cliente guardado deja un envio PENDIENTE en SYNC_SALIDA, aunque no haya red.
-- La central lo recoge por el enlace cuando ejecuta SP_CICLO_SYNC (ver CENTRAL/2_sincronizacion.sql).


-- PARTE A. FACTURAR Y BLOQUES DE NUMERACION

CREATE OR REPLACE PROCEDURE SP_SOLICITAR_BLOQUE (
    pIdSucursal IN NUMBER
) AS
    PRAGMA AUTONOMOUS_TRANSACTION;
    cantidadSolicitudes NUMBER;
BEGIN
    SELECT COUNT(*) INTO cantidadSolicitudes
    FROM SYNC_SALIDA
    WHERE tablaOrigenSalida = 'RANGO_FACTURA'
      AND claveRegistroSalida = TO_CHAR(pIdSucursal)
      AND destinoSalida = 'CENTRAL'
      AND estadoSalida IN ('PENDIENTE', 'ENVIADO');

    IF cantidadSolicitudes = 0 THEN
        INSERT INTO SYNC_SALIDA (
            tablaOrigenSalida, claveRegistroSalida, destinoSalida,
            versionSalida, estadoSalida, fechaCreacionSalida
        ) VALUES (
            'RANGO_FACTURA', TO_CHAR(pIdSucursal), 'CENTRAL',
            1, 'PENDIENTE', SYSDATE
        );
    END IF;
    COMMIT;
END;
/
SHOW ERRORS PROCEDURE SP_SOLICITAR_BLOQUE

CREATE OR REPLACE PROCEDURE SP_EMITIR_FACTURA (
    pIdSucursal IN NUMBER,
    pIdSucursalCliente IN NUMBER,
    pIdClienteLocal IN NUMBER,
    pDetalles IN CLOB,
    pIdFactura OUT NUMBER
) AS
    idRangoActual NUMBER;
    numeroInicialActual NUMBER;
    numeroFinalActual NUMBER;
    proximoNumeroActual NUMBER;
    precioActual NUMBER(12,2);
    totalActual NUMBER(14,2) := 0;
    cantidadLineas NUMBER := 0;
    cantidadSolicitudes NUMBER;
BEGIN
    IF pDetalles IS NULL THEN
        RAISE_APPLICATION_ERROR(-20011, 'La factura necesita detalles');
    END IF;

    BEGIN
        SELECT idRango, numeroInicialRango, numeroFinalRango, proximoNumeroRango
        INTO idRangoActual, numeroInicialActual, numeroFinalActual, proximoNumeroActual
        FROM RANGO_FACTURA
        WHERE idRango = (
            SELECT MIN(idRango)
            FROM RANGO_FACTURA
            WHERE idSucursal = pIdSucursal
              AND estadoRango = 'ACTIVO'
              AND proximoNumeroRango <= numeroFinalRango
        )
        FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            SP_SOLICITAR_BLOQUE(pIdSucursal);
            RAISE_APPLICATION_ERROR(-20010, 'Sin numeros de factura disponibles');
    END;

    pIdFactura := proximoNumeroActual;
    INSERT INTO FACTURA (
        idFactura, idSucursalEmisora, idSucursalCliente,
        idClienteLocal, fechaEmisionFactura, totalFactura
    ) VALUES (
        pIdFactura, pIdSucursal, pIdSucursalCliente,
        pIdClienteLocal, SYSDATE, 0
    );

    FOR lineaActual IN (
        SELECT lineaDetalle, idProducto, cantidadDetalle
        FROM JSON_TABLE(
            pDetalles, '$[*]'
            COLUMNS (
                lineaDetalle FOR ORDINALITY,
                idProducto NUMBER PATH '$.idProducto' ERROR ON ERROR,
                cantidadDetalle NUMBER PATH '$.cantidad' ERROR ON ERROR
            )
        )
    ) LOOP
        IF lineaActual.cantidadDetalle IS NULL OR lineaActual.cantidadDetalle <= 0 THEN
            RAISE_APPLICATION_ERROR(-20012, 'La cantidad debe ser positiva');
        END IF;

        SELECT precioActualProducto INTO precioActual
        FROM PRODUCTO WHERE idProducto = lineaActual.idProducto;

        INSERT INTO DETALLE_FACTURA (
            idFactura, lineaDetalle, idProducto,
            cantidadDetalle, precioUnitarioDetalle
        ) VALUES (
            pIdFactura, lineaActual.lineaDetalle, lineaActual.idProducto,
            lineaActual.cantidadDetalle, precioActual
        );

        totalActual := totalActual + lineaActual.cantidadDetalle * precioActual;
        cantidadLineas := cantidadLineas + 1;
    END LOOP;

    IF cantidadLineas = 0 THEN
        RAISE_APPLICATION_ERROR(-20011, 'La factura necesita al menos un detalle');
    END IF;

    UPDATE FACTURA SET totalFactura = totalActual
    WHERE idFactura = pIdFactura;

    UPDATE RANGO_FACTURA
    SET proximoNumeroRango = proximoNumeroRango + 1,
        estadoRango = CASE
            WHEN proximoNumeroRango + 1 > numeroFinalRango THEN 'AGOTADO'
            ELSE estadoRango
        END
    WHERE idRango = idRangoActual;

    INSERT INTO SYNC_SALIDA (
        tablaOrigenSalida, claveRegistroSalida, destinoSalida,
        versionSalida, estadoSalida, fechaCreacionSalida
    ) VALUES (
        'FACTURA', TO_CHAR(pIdFactura), 'CENTRAL',
        1, 'PENDIENTE', SYSDATE
    );

    IF proximoNumeroActual - numeroInicialActual + 1 >=
       0.8 * (numeroFinalActual - numeroInicialActual + 1) THEN
        SELECT COUNT(*) INTO cantidadSolicitudes
        FROM SYNC_SALIDA
        WHERE tablaOrigenSalida = 'RANGO_FACTURA'
          AND claveRegistroSalida = TO_CHAR(pIdSucursal)
          AND destinoSalida = 'CENTRAL'
          AND estadoSalida IN ('PENDIENTE', 'ENVIADO');

        IF cantidadSolicitudes = 0 THEN
            INSERT INTO SYNC_SALIDA (
                tablaOrigenSalida, claveRegistroSalida, destinoSalida,
                versionSalida, estadoSalida, fechaCreacionSalida
            ) VALUES (
                'RANGO_FACTURA', TO_CHAR(pIdSucursal), 'CENTRAL',
                1, 'PENDIENTE', SYSDATE
            );
        END IF;
    END IF;

    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_EMITIR_FACTURA

-- Retira el bloque activo y pide uno nuevo
CREATE OR REPLACE PROCEDURE SP_RETIRAR_BLOQUE (
    pIdSucursal IN NUMBER
) AS
BEGIN
    UPDATE RANGO_FACTURA SET estadoRango = 'RETIRADO'
    WHERE idSucursal = pIdSucursal
      AND estadoRango = 'ACTIVO';
    COMMIT;
    SP_SOLICITAR_BLOQUE(pIdSucursal);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_RETIRAR_BLOQUE

-- VARIABLE idFactura NUMBER
-- EXEC SP_EMITIR_FACTURA(1, 1, 1,
--   '[{"idProducto":1,"cantidad":1},{"idProducto":5,"cantidad":2}]',
--   :idFactura);
-- PRINT idFactura


-- PARTE B. GUARDAR CLIENTES

CREATE OR REPLACE PROCEDURE SP_GUARDAR_CLIENTE (
    pIdSucursal IN NUMBER,
    pIdClienteLocal IN NUMBER,
    pTipoIdentificacion IN VARCHAR2,
    pNumeroIdentificacion IN VARCHAR2,
    pNombre IN VARCHAR2
) AS
    versionActual NUMBER;
    codigoSucursalActual VARCHAR2(10);
BEGIN
    SELECT codigoSucursal INTO codigoSucursalActual
    FROM SUCURSAL WHERE idSucursal = pIdSucursal;
    IF codigoSucursalActual NOT IN ('SUC01', 'SUC02', 'SUC03') THEN
        RAISE_APPLICATION_ERROR(-20030, 'Debe indicar una sucursal');
    END IF;

    BEGIN
        SELECT versionCliente INTO versionActual
        FROM CLIENTE
        WHERE idSucursalOrigen = pIdSucursal
          AND idClienteLocal = pIdClienteLocal
        FOR UPDATE;

        versionActual := versionActual + 1;
        UPDATE CLIENTE SET
            tipoIdentificacionCliente = pTipoIdentificacion,
            numeroIdentificacionCliente = pNumeroIdentificacion,
            nombreCliente = pNombre,
            versionCliente = versionActual,
            fechaModificacionCliente = SYSDATE
        WHERE idSucursalOrigen = pIdSucursal
          AND idClienteLocal = pIdClienteLocal;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        versionActual := 1;
        INSERT INTO CLIENTE (
            idSucursalOrigen, idClienteLocal, tipoIdentificacionCliente,
            numeroIdentificacionCliente, nombreCliente, versionCliente,
            fechaModificacionCliente
        ) VALUES (
            pIdSucursal, pIdClienteLocal, pTipoIdentificacion,
            pNumeroIdentificacion, pNombre, versionActual, SYSDATE
        );
    END;

    INSERT INTO SYNC_SALIDA (
        tablaOrigenSalida, claveRegistroSalida, destinoSalida,
        versionSalida, estadoSalida, fechaCreacionSalida
    ) VALUES (
        'CLIENTE', TO_CHAR(pIdSucursal) || ':' || TO_CHAR(pIdClienteLocal),
        'CENTRAL', versionActual, 'PENDIENTE', SYSDATE
    );
    COMMIT;
EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END;
/
SHOW ERRORS PROCEDURE SP_GUARDAR_CLIENTE

-- EXEC SP_GUARDAR_CLIENTE(1, 4, 'CEDULA', '404440444', 'Nuevo Cliente');
