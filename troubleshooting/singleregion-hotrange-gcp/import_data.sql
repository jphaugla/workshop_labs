-- create the schema
CREATE TABLE credits (
    id INT2 NOT NULL,
    code UUID NOT NULL,
    channel STRING(1) NOT NULL,
    pid INT4 NOT NULL,
    end_date DATE NOT NULL,
    status STRING(1) NOT NULL,
    start_date DATE NOT NULL,
    CONSTRAINT "primary" PRIMARY KEY (id ASC, code ASC),
    INDEX credits_pid_idx (pid ASC),
    INDEX credits_code_id_idx (code ASC, id ASC) STORING (channel, status, end_date, start_date),
    FAMILY "primary" (id, code, channel, pid, end_date, status, start_date)
);

CREATE TABLE offers (
    id INT4 NOT NULL,
    code UUID NOT NULL,
    token UUID NOT NULL,
    start_date DATE,
    end_date DATE,
    CONSTRAINT "primary" PRIMARY KEY (id ASC, code ASC, token ASC),
    INDEX offers_token_idx (token ASC),
    FAMILY "primary" (id, code, token)
);

-- import the dataset
IMPORT INTO credits CSV DATA ('nodelocal://1/c.csv');