-- Ejecutar en SUC01, SUC02 y SUC03 despues de crear las tablas.
-- pIdSucursal debe ser el numero de esta sucursal (1, 2 o 3).

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

-- Ejemplo SUC01: crea el cliente 4; otra llamada con la misma llave lo actualiza.
-- EXEC SP_GUARDAR_CLIENTE(1, 4, 'CEDULA', '404440444', 'Nuevo Cliente');
