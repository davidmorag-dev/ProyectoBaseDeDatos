-- CENTRAL. Sincronizacion por correo con SUC03. Se ejecuta despues de 2_conectado.sql.
-- Antes, como SYSTEM en XEPDB1:
--   CREATE DIRECTORY DIR_SYNC AS 'C:\sync';
--   GRANT READ, WRITE ON DIRECTORY DIR_SYNC TO CENTRAL;
--   GRANT CREATE JOB TO CENTRAL;

------------------------------------------------------------
-- FN_SIGUIENTE_PAQUETE
-- numero del siguiente paquete para un destino
------------------------------------------------------------
CREATE OR REPLACE FUNCTION FN_SIGUIENTE_PAQUETE (pDestino IN VARCHAR2) RETURN NUMBER AS
    vNumero NUMBER;
BEGIN
    SELECT COUNT(*) + 1 INTO vNumero FROM BITACORA_SYNC
    WHERE contraparteBitacora = pDestino AND direccionBitacora = 'LOTE_GEN' AND resultadoBitacora = 'OK';
    RETURN vNumero;
END;
/

------------------------------------------------------------
-- SP_GENERAR_PAQUETE
-- escribe el archivo con los envios pendientes para pDestino. Cada linea lleva su huella
-- ENC es el encabezado, ENV un envio y ACK el acuse de lo que ya se recibio del destino
------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_GENERAR_PAQUETE (pOrigen IN VARCHAR2, pDestino IN VARCHAR2, pNumero IN NUMBER) AS
    vArchivo UTL_FILE.FILE_TYPE;
    vInicio DATE := SYSDATE;
    vMaximo NUMBER;
    vCantidad NUMBER;
    vDatos VARCHAR2(4000);
    vNombre VARCHAR2(60);
BEGIN
    SELECT NVL(MAX(idSalida), 0), COUNT(*) INTO vMaximo, vCantidad FROM SYNC_SALIDA
    WHERE destinoSalida = pDestino AND estadoSalida <> 'APLICADO';

    IF pOrigen = 'CENTRAL' THEN
        vNombre := 'respuesta_' || pDestino || '_' || LPAD(pNumero, 4, '0') || '.txt';
    ELSE
        vNombre := 'lote_' || pOrigen || '_' || LPAD(pNumero, 4, '0') || '.txt';
    END IF;
    vArchivo := UTL_FILE.FOPEN('DIR_SYNC', vNombre, 'W', 32767);
    UTL_FILE.PUT_LINE(vArchivo, 'ENC;' || pOrigen || ';' || pDestino || ';' || pNumero || ';' ||
        TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') || ';' || vCantidad);

    FOR e IN (SELECT idSalida, tablaOrigenSalida, claveRegistroSalida, versionSalida FROM SYNC_SALIDA
              WHERE destinoSalida = pDestino AND estadoSalida <> 'APLICADO' AND idSalida <= vMaximo ORDER BY idSalida) LOOP
        vDatos := FN_SERIALIZAR(e.tablaOrigenSalida, e.claveRegistroSalida, pDestino);
        UTL_FILE.PUT_LINE(vArchivo, 'ENV;' || e.idSalida || ';' || e.tablaOrigenSalida || ';' || e.claveRegistroSalida || ';' ||
            e.versionSalida || ';' || vDatos || ';' || FN_HUELLA(vDatos));
    END LOOP;

    FOR a IN (SELECT idEnvioRecibido FROM SYNC_RECIBIDO WHERE origenRecibido = pDestino ORDER BY idEnvioRecibido) LOOP
        UTL_FILE.PUT_LINE(vArchivo, 'ACK;' || a.idEnvioRecibido);
    END LOOP;
    UTL_FILE.FCLOSE(vArchivo);

    -- quedan como enviados hasta que llegue el acuse
    UPDATE SYNC_SALIDA SET estadoSalida = 'ENVIADO', fechaEnvioSalida = SYSDATE
    WHERE destinoSalida = pDestino AND estadoSalida <> 'APLICADO' AND idSalida <= vMaximo;
    COMMIT;
    SP_REGISTRAR_BITACORA(pDestino, 'LOTE_GEN', 'LOTE', vInicio, 'OK');
EXCEPTION WHEN OTHERS THEN
    IF UTL_FILE.IS_OPEN(vArchivo) THEN
        UTL_FILE.FCLOSE(vArchivo);
    END IF;
    ROLLBACK;
    SP_REGISTRAR_BITACORA(pDestino, 'LOTE_GEN', 'LOTE', vInicio, 'ERROR');
    RAISE;
END;
/

------------------------------------------------------------
-- SP_PROCESAR_PAQUETE
-- lee un paquete, comprueba que llego completo y sin alteraciones, y lo aplica en una sola transaccion
------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_PROCESAR_PAQUETE (pArchivo IN VARCHAR2, pOrigen IN VARCHAR2, pDestino IN VARCHAR2) AS
    TYPE tLineas IS TABLE OF VARCHAR2(4000) INDEX BY PLS_INTEGER;
    vLineas tLineas;
    vArchivo UTL_FILE.FILE_TYPE;
    vLinea VARCHAR2(4000);
    vTotal PLS_INTEGER := 0;
    vEnvios NUMBER := 0;
    vAplicados NUMBER := 0;
    vInicio DATE := SYSDATE;
    vResultado VARCHAR2(10);
BEGIN
    -- se lee todo el archivo
    vArchivo := UTL_FILE.FOPEN('DIR_SYNC', pArchivo, 'R', 32767);
    BEGIN
        LOOP
            UTL_FILE.GET_LINE(vArchivo, vLinea);
            vTotal := vTotal + 1;
            vLineas(vTotal) := vLinea;
        END LOOP;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        NULL;
    END;
    UTL_FILE.FCLOSE(vArchivo);

    -- integridad: encabezado, huella de cada envio y cantidad. Si algo falla no se aplica nada
    IF vTotal = 0 OR FN_CAMPO(vLineas(1), ';', 1) <> 'ENC' OR FN_CAMPO(vLineas(1), ';', 2) <> pOrigen
       OR FN_CAMPO(vLineas(1), ';', 3) <> pDestino THEN
        RAISE_APPLICATION_ERROR(-20040, 'El encabezado del paquete no es valido');
    END IF;
    FOR i IN 2 .. vTotal LOOP
        IF FN_CAMPO(vLineas(i), ';', 1) = 'ENV' THEN
            vEnvios := vEnvios + 1;
            IF FN_HUELLA(FN_CAMPO(vLineas(i), ';', 6)) <> FN_CAMPO(vLineas(i), ';', 7) THEN
                RAISE_APPLICATION_ERROR(-20041, 'El envio ' || FN_CAMPO(vLineas(i), ';', 2) || ' llego alterado');
            END IF;
        END IF;
    END LOOP;
    IF vEnvios <> TO_NUMBER(FN_CAMPO(vLineas(1), ';', 6)) THEN
        RAISE_APPLICATION_ERROR(-20042, 'El paquete llego incompleto');
    END IF;

    -- se aplican los envios en orden y se procesan los acuses
    FOR i IN 2 .. vTotal LOOP
        IF FN_CAMPO(vLineas(i), ';', 1) = 'ENV' THEN
            SP_APLICAR_ENVIO(pOrigen, TO_NUMBER(FN_CAMPO(vLineas(i), ';', 2)), FN_CAMPO(vLineas(i), ';', 3),
                FN_CAMPO(vLineas(i), ';', 4), TO_NUMBER(FN_CAMPO(vLineas(i), ';', 5)), FN_CAMPO(vLineas(i), ';', 6), vResultado);
            IF vResultado <> 'OMITIDO' THEN
                vAplicados := vAplicados + 1;
            END IF;
        ELSIF FN_CAMPO(vLineas(i), ';', 1) = 'ACK' THEN
            UPDATE SYNC_SALIDA SET estadoSalida = 'APLICADO', fechaAplicacionSalida = SYSDATE
            WHERE idSalida = TO_NUMBER(FN_CAMPO(vLineas(i), ';', 2)) AND destinoSalida = pOrigen AND estadoSalida <> 'APLICADO';
        END IF;
    END LOOP;

    UPDATE SUCURSAL SET fechaUltimaSyncSucursal = SYSDATE WHERE codigoSucursal = pOrigen;
    COMMIT;
    SP_REGISTRAR_BITACORA(pOrigen, 'LOTE_APL', 'LOTE', vInicio, CASE WHEN vAplicados = 0 AND vEnvios > 0 THEN 'OMITIDO' ELSE 'OK' END);
EXCEPTION WHEN OTHERS THEN
    IF UTL_FILE.IS_OPEN(vArchivo) THEN
        UTL_FILE.FCLOSE(vArchivo);
    END IF;
    ROLLBACK;
    SP_REGISTRAR_BITACORA(pOrigen, 'LOTE_APL', 'LOTE', vInicio, 'ERROR');
    RAISE;
END;
/

------------------------------------------------------------
-- SP_ENVIAR_RESPUESTA
-- la central responde a SUC03 todos los dias a las 9 p. m.
------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_ENVIAR_RESPUESTA AS
BEGIN
    SP_GENERAR_PAQUETE('CENTRAL', 'SUC03', FN_SIGUIENTE_PAQUETE('SUC03'));
END;
/
-- trabajo programado
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(job_name => 'JOB_RESPUESTA_SUC03', job_type => 'STORED_PROCEDURE',
        job_action => 'SP_ENVIAR_RESPUESTA', repeat_interval => 'FREQ=DAILY;BYHOUR=21;BYMINUTE=0;BYSECOND=0',
        enabled => TRUE);
END;
/

-- errores de compilacion de este archivo (si no sale nada, todo bien)
SELECT name, line, text FROM user_errors ORDER BY name, sequence;
