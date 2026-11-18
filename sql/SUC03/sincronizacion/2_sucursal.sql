-- SUC03. Facturar y guardar clientes. Cada cambio deja un envio pendiente en SYNC_SALIDA.
-- Se ejecuta despues de 1_motor.sql.

------------------------------------------------------------
-- SP_SOLICITAR_BLOQUE
-- pide un bloque nuevo a la central, si no hay una solicitud pendiente
------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_SOLICITAR_BLOQUE (pIdSucursal IN NUMBER) AS
    vPendientes NUMBER;
BEGIN
    SELECT COUNT(*) INTO vPendientes FROM SYNC_SALIDA
    WHERE tablaOrigenSalida = 'RANGO_FACTURA' AND destinoSalida = 'CENTRAL' AND estadoSalida <> 'APLICADO';
    IF vPendientes = 0 THEN
        SP_NUEVO_ENVIO('RANGO_FACTURA', pIdSucursal, 'CENTRAL', 1);
    END IF;
    COMMIT;
END;
/

------------------------------------------------------------
-- SP_EMITIR_FACTURA
-- emite una factura con el siguiente numero del bloque. pDetalles va como 'producto:cantidad;producto:cantidad'
------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_EMITIR_FACTURA (
    pIdSucursal IN NUMBER, pIdSucursalCliente IN NUMBER, pIdClienteLocal IN NUMBER,
    pDetalles IN VARCHAR2, pIdFactura OUT NUMBER
) AS
    vRango RANGO_FACTURA%ROWTYPE;
    vLinea VARCHAR2(50);
    vProducto NUMBER;
    vCantidad NUMBER;
    vPrecio NUMBER;
    vTotal NUMBER := 0;
    i NUMBER := 1;
BEGIN
    -- bloque activo con numeros disponibles
    BEGIN
        SELECT * INTO vRango FROM RANGO_FACTURA
        WHERE idSucursal = pIdSucursal AND estadoRango = 'ACTIVO' AND proximoNumeroRango <= numeroFinalRango AND ROWNUM = 1
        FOR UPDATE;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        SP_SOLICITAR_BLOQUE(pIdSucursal);
        RAISE_APPLICATION_ERROR(-20010, 'No hay numeros de factura disponibles');
    END;

    pIdFactura := vRango.proximoNumeroRango;
    INSERT INTO FACTURA VALUES (pIdFactura, pIdSucursal, pIdSucursalCliente, pIdClienteLocal, SYSDATE, 0);

    LOOP
        vLinea := FN_CAMPO(pDetalles, ';', i);
        EXIT WHEN vLinea IS NULL;
        vProducto := TO_NUMBER(FN_CAMPO(vLinea, ':', 1));
        vCantidad := TO_NUMBER(FN_CAMPO(vLinea, ':', 2));
        SELECT precioActualProducto INTO vPrecio FROM PRODUCTO WHERE idProducto = vProducto;
        INSERT INTO DETALLE_FACTURA VALUES (pIdFactura, i, vProducto, vCantidad, vPrecio);
        vTotal := vTotal + vCantidad * vPrecio;
        i := i + 1;
    END LOOP;
    IF i = 1 THEN
        RAISE_APPLICATION_ERROR(-20011, 'La factura necesita al menos un detalle');
    END IF;
    UPDATE FACTURA SET totalFactura = vTotal WHERE idFactura = pIdFactura;

    -- se usa el numero y si era el ultimo el bloque queda agotado
    UPDATE RANGO_FACTURA SET proximoNumeroRango = proximoNumeroRango + 1,
        estadoRango = CASE WHEN proximoNumeroRango + 1 > numeroFinalRango THEN 'AGOTADO' ELSE estadoRango END
    WHERE idRango = vRango.idRango;

    SP_NUEVO_ENVIO('FACTURA', pIdFactura, 'CENTRAL', 1);

    -- al usar el 80% del bloque se pide otro
    IF vRango.proximoNumeroRango - vRango.numeroInicialRango + 1 >= 0.8 * (vRango.numeroFinalRango - vRango.numeroInicialRango + 1) THEN
        SP_SOLICITAR_BLOQUE(pIdSucursal);
    END IF;
    COMMIT;
EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END;
/

------------------------------------------------------------
-- SP_RETIRAR_BLOQUE
-- se usa despues de restaurar una copia vieja: el bloque activo se retira y se pide otro
------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_RETIRAR_BLOQUE (pIdSucursal IN NUMBER) AS
BEGIN
    UPDATE RANGO_FACTURA SET estadoRango = 'RETIRADO' WHERE idSucursal = pIdSucursal AND estadoRango = 'ACTIVO';
    SP_SOLICITAR_BLOQUE(pIdSucursal);
END;
/

------------------------------------------------------------
-- SP_GUARDAR_CLIENTE
-- crea el cliente o, si ya existe, le sube la version
------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_GUARDAR_CLIENTE (
    pIdSucursal IN NUMBER, pIdClienteLocal IN NUMBER, pTipo IN VARCHAR2, pNumero IN VARCHAR2, pNombre IN VARCHAR2
) AS
    vVersion NUMBER;
BEGIN
    UPDATE CLIENTE SET tipoIdentificacionCliente = pTipo, numeroIdentificacionCliente = pNumero, nombreCliente = pNombre,
        versionCliente = versionCliente + 1, fechaModificacionCliente = SYSDATE
    WHERE idSucursalOrigen = pIdSucursal AND idClienteLocal = pIdClienteLocal;
    IF SQL%ROWCOUNT = 0 THEN
        INSERT INTO CLIENTE VALUES (pIdSucursal, pIdClienteLocal, pTipo, pNumero, pNombre, 1, SYSDATE);
    END IF;
    SELECT versionCliente INTO vVersion FROM CLIENTE WHERE idSucursalOrigen = pIdSucursal AND idClienteLocal = pIdClienteLocal;
    SP_NUEVO_ENVIO('CLIENTE', pIdSucursal || ':' || pIdClienteLocal, 'CENTRAL', vVersion);
    COMMIT;
EXCEPTION WHEN OTHERS THEN
    ROLLBACK;
    RAISE;
END;
/


-- errores de compilacion de este archivo (si no sale nada, todo bien)
SELECT name, line, text FROM user_errors ORDER BY name, sequence;
