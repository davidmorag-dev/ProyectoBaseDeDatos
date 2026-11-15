-- Ejecutar solo en CENTRAL, despues de 6_aplicarPaqueteCorreo.sql.
-- Genera la respuesta por correo para una sucursal en modo diferido (SUC03):
-- cambios del catalogo, clientes de otras sucursales, bloques nuevos y acuses.
-- Usa la carpeta DIR_SYNC y las funciones FN_CAMPO y FN_HUELLA del archivo 6.

-- Convierte un registro pendiente en una linea de texto.
-- Producto: descripcion~precio~fecha
-- Cliente: tipo~numero~nombre~version~fecha
-- Bloque: sucursal~inicial~final~proximo~estado
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

-- Numero de la proxima respuesta para una sucursal.
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

-- Escribe respuesta_SUC03_000N.txt en DIR_SYNC con todo lo que la central tiene
-- pendiente para esa sucursal y los acuses de los envios que ya aplico.
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

    -- Acuses: envios de la sucursal que la central ya aplico o descarto.
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

-- Genera la respuesta sola, todos los dias a las 9 p. m. (una hora despues del lote de SUC03).
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'JOB_RESPUESTA_SUC03',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN SP_GENERAR_RESPUESTA(''SUC03'', FN_SIGUIENTE_RESPUESTA(''SUC03'')); END;',
        repeat_interval => 'FREQ=DAILY;BYHOUR=21;BYMINUTE=0;BYSECOND=0',
        enabled         => TRUE);
END;
/

-- A demanda:
-- EXEC SP_GENERAR_RESPUESTA('SUC03', FN_SIGUIENTE_RESPUESTA('SUC03'));
