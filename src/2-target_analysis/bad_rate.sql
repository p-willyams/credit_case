 WITH RECURSIVE parametros AS (
    SELECT
        date(:data_corte)             AS data_corte,
        CAST(:n_meses AS INTEGER)     AS n_meses
),

contratos AS (
    SELECT h.id_contrato, date(h.data_decisao) AS data_decisao
    FROM base_historico_emprestimos h
    CROSS JOIN parametros p
    WHERE h.status_contrato = 'Aprovado'

      AND date(h.data_decisao, '+' || p.n_meses || ' months') <= p.data_corte
),


parcelas_janela AS (
    SELECT
        c.id_contrato,
        c.data_decisao,
        date(d.data_prevista_pagamento) AS venc,
        date(d.data_quitacao)           AS quitacao
    FROM contratos c
    JOIN base_dividas d ON d.id_contrato = c.id_contrato
    CROSS JOIN parametros p
    WHERE COALESCE(d.previsto_invalido, 0) = 0
      AND date(d.data_prevista_pagamento) < date(c.data_decisao, '+' || p.n_meses || ' months')
),


populacao AS (
    SELECT id_contrato, data_decisao
    FROM parcelas_janela
    GROUP BY id_contrato, data_decisao


),


ever AS (
    SELECT
        pj.id_contrato,



        MAX(MAX(0, CAST(julianday(COALESCE(pj.quitacao, p.data_corte))
                          - julianday(pj.venc) AS INTEGER))) AS max_ever
    FROM parcelas_janela pj
    JOIN populacao po ON po.id_contrato = pj.id_contrato
    CROSS JOIN parametros p
    GROUP BY pj.id_contrato
),

meses_k AS (
    SELECT 0 AS k
    UNION ALL
    SELECT m.k + 1
    FROM meses_k m
    CROSS JOIN parametros p
    WHERE m.k + 1 <= p.n_meses
),


over_snap AS (
    SELECT
        po.id_contrato,
        m.k,
        MAX(CASE
                WHEN pj.venc < date(po.data_decisao, '+' || m.k || ' months')
                 AND (pj.quitacao IS NULL
                      OR pj.quitacao > date(po.data_decisao, '+' || m.k || ' months'))



                THEN CAST(julianday(date(po.data_decisao, '+' || m.k || ' months'))
                              - julianday(pj.venc) AS INTEGER)
                ELSE 0
            END) AS over_dias
    FROM populacao po
    CROSS JOIN meses_k m
    JOIN parcelas_janela pj ON pj.id_contrato = po.id_contrato
    CROSS JOIN parametros p
    GROUP BY po.id_contrato, m.k
),

over_max AS (
    SELECT id_contrato, MAX(over_dias) AS max_over
    FROM over_snap
    GROUP BY id_contrato
)

SELECT po.id_contrato, po.data_decisao, e.max_ever, o.max_over
FROM populacao po
JOIN ever     e ON e.id_contrato = po.id_contrato
JOIN over_max o ON o.id_contrato = po.id_contrato;