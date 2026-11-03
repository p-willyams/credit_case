WITH tb_emprestimos AS (
    SELECT *
    FROM base_historico_emprestimos
    WHERE status_contrato = 'Aprovado'
),

tb_cadastral AS (
    SELECT
        id_cliente,
        renda_anual
    FROM base_cadastral
),

-- Contratos anteriores ativos
tb_contratos_anteriores AS (
    SELECT
        t1.id_cliente,
        t1.id_contrato AS id_contrato_atual,
        t1.data_decisao AS data_ref,

        t2.id_contrato AS id_contrato_anterior,
        t2.valor_parcela,
        t2.valor_credito

    FROM tb_emprestimos AS t1

    INNER JOIN tb_emprestimos AS t2
        ON t1.id_cliente = t2.id_cliente
       AND t1.id_contrato <> t2.id_contrato
       AND date(t2.data_decisao) < date(t1.data_decisao)
       AND date(t2.data_liberacao) <= date(t1.data_decisao)
       AND (
           t2.data_encerramento IS NULL
           OR date(t2.data_encerramento) > date(t1.data_decisao)
       )
),

-- Soma das parcelas mensais dos contratos anteriores
tb_parcelas_mensais AS (
    SELECT
        id_cliente,
        id_contrato_atual,
        data_ref,
        SUM(valor_parcela) AS parcela_mensal_aberta

    FROM tb_contratos_anteriores

    GROUP BY
        id_cliente,
        id_contrato_atual,
        data_ref
),

-- Média histórica de crédito dos contratos anteriores
tb_media_credito_historico AS (
    SELECT
        id_cliente,
        id_contrato_atual,
        data_ref,
        AVG(valor_credito) AS media_credito_historico

    FROM tb_contratos_anteriores

    GROUP BY
        id_cliente,
        id_contrato_atual,
        data_ref
),

-- Média histórica das parcelas dos contratos anteriores
tb_media_parcela_historico AS (
    SELECT
        id_cliente,
        id_contrato_atual,
        data_ref,
        AVG(valor_parcela) AS media_parcela_historica

    FROM tb_contratos_anteriores

    GROUP BY
        id_cliente,
        id_contrato_atual,
        data_ref
),

-- Parcelas dos contratos anteriores
tb_parcelas AS (
    SELECT
        c.id_cliente,
        c.id_contrato_atual,
        c.data_ref,
        d.id_contrato,
        d.numero_parcela,
        d.versao_parcela,
        d.valor_previsto_parcela

    FROM tb_contratos_anteriores AS c

    INNER JOIN base_dividas AS d
        ON c.id_contrato_anterior = d.id_contrato

    WHERE d.previsto_invalido = 0
),

-- Saldo devedor de cada parcela na data_ref
tb_saldo_parcelas AS (
    SELECT
        p.id_cliente,
        p.id_contrato_atual,
        p.data_ref,
        p.id_contrato,
        p.numero_parcela,
        p.versao_parcela,

        p.valor_previsto_parcela - COALESCE((
            SELECT SUM(pg.valor_pago_parcela)
            FROM base_pagamentos AS pg
            WHERE pg.id_contrato = p.id_contrato
            AND pg.numero_parcela = p.numero_parcela
            AND date(pg.data_real_pagamento) <= date(p.data_ref)
        ), 0) AS saldo_parcela

    FROM tb_parcelas AS p
),

-- Exposição financeira dos contratos anteriores
tb_exposicao_anterior AS (
    SELECT
        id_cliente,
        id_contrato_atual,
        data_ref,
        SUM(saldo_parcela) AS saldo_aberto_estimado

    FROM tb_saldo_parcelas

    GROUP BY
        id_cliente,
        id_contrato_atual,
        data_ref
),

tb_features AS (
    SELECT
        t1.id_cliente,
        t1.id_contrato,
        t1.data_decisao AS data_ref,

        t1.valor_parcela AS valor_parcela_atual,
        t1.valor_solicitado AS valor_credito_atual,

        t2.renda_anual,
        t2.renda_anual / 12.0 AS renda_mensal,

        COALESCE(t3.parcela_mensal_aberta, 0)
            AS parcela_mensal_aberta,

        t4.media_credito_historico,
        t5.media_parcela_historica,

        COALESCE(t6.saldo_aberto_estimado, 0)
            AS saldo_aberto_estimado

    FROM tb_emprestimos AS t1

    LEFT JOIN tb_cadastral AS t2
        ON t1.id_cliente = t2.id_cliente

    LEFT JOIN tb_parcelas_mensais AS t3
        ON t1.id_contrato = t3.id_contrato_atual

    LEFT JOIN tb_media_credito_historico AS t4
        ON t1.id_contrato = t4.id_contrato_atual

    LEFT JOIN tb_media_parcela_historico AS t5
        ON t1.id_contrato = t5.id_contrato_atual

    LEFT JOIN tb_exposicao_anterior AS t6
        ON t1.id_contrato = t6.id_contrato_atual
)

SELECT
    id_cliente,
    id_contrato,
    data_ref,

    valor_parcela_atual / renda_mensal
        AS parcela_sobre_renda_mensal,

    valor_credito_atual / renda_anual
        AS credito_sobre_renda_anual,

    valor_parcela_atual,
    parcela_mensal_aberta,

    (valor_parcela_atual + parcela_mensal_aberta)
        / renda_mensal AS comprometimento_renda,

    media_parcela_historica,

    valor_parcela_atual / media_parcela_historica
        AS parcela_atual_sobre_parcela_media_hist,

    valor_credito_atual,
    media_credito_historico,

    valor_credito_atual / media_credito_historico
        AS credito_atual_sobre_media_historica,

    saldo_aberto_estimado,

    (valor_credito_atual + saldo_aberto_estimado)
        / renda_anual AS exposicao_total_sobre_renda

FROM tb_features

LIMIT 10;