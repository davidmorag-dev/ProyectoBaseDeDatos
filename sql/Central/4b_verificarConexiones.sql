-- Ejecutar completo con F5 en CENTRAL.
-- Solo comprueba si cada enlace responde; no cambia datos.
SET SERVEROUTPUT ON

-- ---------------------------------
-- 1. VERIFICAR SUC01
-- ---------------------------------
DECLARE
    respuesta NUMBER;
BEGIN
    SELECT 1 INTO respuesta FROM DUAL@LNK_SUC01;
    DBMS_OUTPUT.PUT_LINE('SUC01: ONLINE');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('SUC01: OFFLINE (Oracle ' || SQLCODE || ')');
END;
/

-- ---------------------------------
-- 2. VERIFICAR SUC02
-- ---------------------------------
DECLARE
    respuesta NUMBER;
BEGIN
    SELECT 1 INTO respuesta FROM DUAL@LNK_SUC02;
    DBMS_OUTPUT.PUT_LINE('SUC02: ONLINE');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('SUC02: OFFLINE (Oracle ' || SQLCODE || ')');
END;
/

-- ---------------------------------
-- 3. SUC03 NO USA ENLACE DIRECTO
-- ---------------------------------
PROMPT SUC03: CORREO (sin enlace directo)
