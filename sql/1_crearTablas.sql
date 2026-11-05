-- SUCURSAL
CREATE TABLE SUCURSAL (
    idSucursal                        NUMBER(3)      PRIMARY KEY,
    codigoSucursal                    VARCHAR2(10)   NOT NULL UNIQUE,
    nombreSucursal                    VARCHAR2(60)   NOT NULL,
    estadoConexionSucursal            VARCHAR2(10)   DEFAULT 'CONECTADA' NOT NULL
                                      CHECK (estadoConexionSucursal IN ('CONECTADA', 'DIFERIDA')),
    fechaUltimaSincronizacionSucursal TIMESTAMP
);
