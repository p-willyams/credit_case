WITH RECURSIVE configuracao AS (
    SELECT
        date(:data_corte)             AS data_limite_analise,
        CAST(:n_meses AS INTEGER)     AS meses_janela_observacao
),

base_parcelas AS (
    SELECT
        d.id_contrato,
        d.numero_parcela,
        date(h.data_decisao)            AS data_aprovacao,
        date(d.data_prevista_pagamento) AS data_vencimento,
        date(d.data_quitacao)           AS data_pagamento_real
    FROM base_dividas d
    JOIN base_historico_emprestimos h
         ON h.id_contrato = d.id_contrato
        AND h.status_contrato = 'Aprovado'
    WHERE COALESCE(d.previsto_invalido, 0) = 0
),

calendario_mensal AS (
    SELECT
        1 AS indice_mes,
        date(MIN(data_aprovacao), 'start of month', '+1 month', '-1 day') AS data_referencia
    FROM base_parcelas
    UNION ALL
    SELECT
        m.indice_mes + 1,
        date(m.data_referencia, 'start of month', '+2 months', '-1 day')
    FROM calendario_mensal m
    CROSS JOIN configuracao c
    WHERE date(m.data_referencia, 'start of month', '+2 months', '-1 day') <= c.data_limite_analise
),

status_atraso_mensal AS (
    SELECT
        m.indice_mes,
        m.data_referencia,
        p.id_contrato,
        MAX(CASE
                WHEN p.data_vencimento < m.data_referencia
                 AND (p.data_pagamento_real IS NULL OR p.data_pagamento_real > m.data_referencia)
                THEN CAST(julianday(m.data_referencia) - julianday(p.data_vencimento) AS INTEGER)
                ELSE 0
            END) AS dias_em_atraso,
        SUM(CASE WHEN p.data_vencimento < m.data_referencia THEN 1 ELSE 0 END) AS qtd_parcelas_vencidas,
        SUM(CASE WHEN p.data_pagamento_real IS NULL OR p.data_pagamento_real > m.data_referencia
                 THEN 1 ELSE 0 END) AS qtd_parcelas_em_aberto
    FROM calendario_mensal m
    JOIN base_parcelas p
         ON p.data_aprovacao <= m.data_referencia
    GROUP BY m.indice_mes, m.data_referencia, p.id_contrato
),

consolidado_janela AS (
    SELECT
        s_inicio.data_referencia        AS data_base_analise,
        s_inicio.id_contrato,
        s_inicio.dias_em_atraso         AS atraso_inicial,
        MAX(s_janela.dias_em_atraso)    AS maior_atraso_no_periodo,
        MAX(CASE
                WHEN s_janela.indice_mes = s_inicio.indice_mes + c.meses_janela_observacao
                THEN s_janela.dias_em_atraso
            END) AS atraso_final_janela
    FROM status_atraso_mensal s_inicio
    CROSS JOIN configuracao c
    JOIN status_atraso_mensal s_janela
         ON s_janela.id_contrato = s_inicio.id_contrato
        AND s_janela.indice_mes BETWEEN s_inicio.indice_mes AND s_inicio.indice_mes + c.meses_janela_observacao
    WHERE s_inicio.indice_mes + c.meses_janela_observacao <= (SELECT MAX(indice_mes) FROM calendario_mensal)
    GROUP BY s_inicio.data_referencia, s_inicio.id_contrato, s_inicio.dias_em_atraso
),

classificacao_faixas AS (
    SELECT
        *,
        CASE
            WHEN atraso_inicial = 0                  THEN '00 - Em Dia'
            WHEN atraso_inicial BETWEEN 1   AND 30   THEN '01 - (1-30 dias)'
            WHEN atraso_inicial BETWEEN 31  AND 60   THEN '02 - (31-60 dias)'
            WHEN atraso_inicial BETWEEN 61  AND 90   THEN '03 - (61-90 dias)'
            WHEN atraso_inicial BETWEEN 91  AND 120  THEN '04 - (91-120 dias)'
            WHEN atraso_inicial BETWEEN 121 AND 180  THEN '05 - (121-180 dias)'
            ELSE                                          '06 - (180+ dias)'
        END AS faixa_atraso_referencia
    FROM consolidado_janela
)

SELECT
    faixa_atraso_referencia,
    COUNT(*)                     AS total_observacoes,
    COUNT(DISTINCT id_contrato)  AS total_contratos_unicos,

    CASE WHEN faixa_atraso_referencia <> '00 - Em Dia'
         THEN ROUND(100.0 * AVG(atraso_final_janela = 0), 2)
         END AS perc_recuperacao_total_cura,
    CASE WHEN faixa_atraso_referencia <> '00 - Em Dia'
         THEN ROUND(100.0 * AVG(atraso_final_janela > 0 AND atraso_final_janela < atraso_inicial), 2)
         END AS perc_melhora_atraso,

    CASE WHEN faixa_atraso_referencia = '00 - Em Dia'
         THEN ROUND(100.0 * AVG(maior_atraso_no_periodo > 0), 2)
         END AS perc_incidencia_atraso_periodo,

    CASE WHEN faixa_atraso_referencia IN ('00 - Em Dia', '01 - (1-30 dias)')
         THEN ROUND(100.0 * AVG(maior_atraso_no_periodo > 30), 2)
         END AS perc_atingiu_atraso_acima_30_no_periodo,

    CASE WHEN faixa_atraso_referencia IN ('00 - Em Dia', '01 - (1-30 dias)', '02 - (31-60 dias)')
         THEN ROUND(100.0 * AVG(maior_atraso_no_periodo > 60), 2)
         END AS perc_atingiu_atraso_acima_60_no_periodo,

    CASE WHEN faixa_atraso_referencia IN ('00 - Em Dia', '01 - (1-30 dias)', '02 - (31-60 dias)', '03 - (61-90 dias)')
         THEN ROUND(100.0 * AVG(maior_atraso_no_periodo > 90), 2)
         END AS perc_atingiu_atraso_acima_90_no_periodo,

    CASE WHEN faixa_atraso_referencia NOT IN ('05 - (121-180 dias)', '06 - (180+ dias)')
         THEN ROUND(100.0 * AVG(maior_atraso_no_periodo > 120), 2)
         END AS perc_atingiu_atraso_acima_120_no_periodo,

    CASE WHEN faixa_atraso_referencia <> '06 - (180+ dias)'
         THEN ROUND(100.0 * AVG(maior_atraso_no_periodo > 180), 2)
         END AS perc_atingiu_atraso_acima_180_no_periodo,

    ROUND(100.0 * AVG(atraso_final_janela > 0),   2) AS perc_final_em_atraso,
    ROUND(100.0 * AVG(atraso_final_janela > 30),  2) AS perc_final_atraso_acima_30,
    ROUND(100.0 * AVG(atraso_final_janela > 60),  2) AS perc_final_atraso_acima_60,
    ROUND(100.0 * AVG(atraso_final_janela > 90),  2) AS perc_final_atraso_acima_90,
    ROUND(100.0 * AVG(atraso_final_janela > 120), 2) AS perc_final_atraso_acima_120,
    ROUND(100.0 * AVG(atraso_final_janela > 180), 2) AS perc_final_atraso_acima_180
FROM classificacao_faixas
GROUP BY faixa_atraso_referencia
ORDER BY faixa_atraso_referencia;
