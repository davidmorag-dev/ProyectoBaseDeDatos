-- Ejecutar solo en CENTRAL, conectado con el usuario dueno del esquema.
-- SQL*Plus solicita las claves; no guardarlas en Git.
-- Verificar antes la IP, el puerto del listener y el servicio de cada sucursal.

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
