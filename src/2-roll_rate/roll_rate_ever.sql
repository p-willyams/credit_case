

WITH RECURSIVE config_parametros AS (
    SELECT
        date(:data_corte)                 AS data_limite_analise,
        CAST(:n_meses AS INTEGER)         AS meses_janela_observacao
),

detalhe_parcelas AS (
    SELECT
        d.id_contrato,
        d.numero_parcela,
        date(h.data_decisao)            AS data_aprovacao_contrato,
        date(d.data_prevista_pagamento) AS data_vencimento,
        date(d.data_quitacao)           AS data_pagamento_efetivo
    FROM base_dividas d
    JOIN base_historico_emprestimos h
         ON h.id_contrato = d.id_contrato
        AND h.status_contrato = 'Aprovado'
    WHERE COALESCE(d.previsto_invalido, 0) = 0
),

sequencia_meses AS (
    SELECT date(MIN(data_aprovacao_contrato), 'start of month', '+1 month', '-1 day') AS data_referencia
    FROM detalhe_parcelas
    UNION ALL
    SELECT date(m.data_referencia, 'start of month', '+2 months', '-1 day')
    FROM sequencia_meses m
    CROSS JOIN config_parametros p
    WHERE date(m.data_referencia, 'start of month', '+2 months', '-1 day') <= p.data_limite_analise
),

intervalos_observacao AS (
    SELECT
        m.data_referencia,
        date(m.data_referencia, 'start of month', '+' || (p.meses_janela_observacao + 1) || ' months', '-1 day') AS data_fim_janela
    FROM sequencia_meses m
    CROSS JOIN config_parametros p
    WHERE date(m.data_referencia, 'start of month', '+' || (p.meses_janela_observacao + 1) || ' months', '-1 day') <= p.data_limite_analise
),

evolucao_atraso_contrato AS (
    SELECT
        i.data_referencia,
        dp.id_contrato,
        MAX(CASE
                WHEN dp.data_vencimento < i.data_referencia
                 AND (dp.data_pagamento_efetivo IS NULL OR dp.data_pagamento_efetivo > i.data_referencia)
                THEN CAST(julianday(i.data_referencia) - julianday(dp.data_vencimento) AS INTEGER)
                ELSE 0
            END) AS dias_atraso_inicio,
        MAX(
            CASE
                WHEN dp.data_vencimento < i.data_fim_janela
                AND (dp.data_pagamento_efetivo IS NULL OR dp.data_pagamento_efetivo > i.data_referencia)
                AND (dp.data_pagamento_efetivo IS NULL OR dp.data_pagamento_efetivo > dp.data_vencimento)
                THEN CAST(
                        julianday(
                            MIN(
                                COALESCE(dp.data_pagamento_efetivo, i.data_fim_janela),
                                i.data_fim_janela
                            )
                        ) - julianday(dp.data_vencimento)
                        AS INTEGER
                    )
                ELSE 0
            END) AS maximo_dias_atraso_na_janela,
        MAX(CASE
                WHEN dp.data_vencimento < i.data_fim_janela
                 AND (dp.data_pagamento_efetivo IS NULL OR dp.data_pagamento_efetivo > i.data_fim_janela)
                THEN CAST(julianday(i.data_fim_janela) - julianday(dp.data_vencimento) AS INTEGER)
                ELSE 0
            END) AS dias_atraso_final
    FROM intervalos_observacao i
    JOIN detalhe_parcelas dp
         ON dp.data_aprovacao_contrato <= i.data_referencia
    GROUP BY i.data_referencia, dp.id_contrato
),

base_classificada AS (
    SELECT
        *,
        CASE
            WHEN dias_atraso_inicio = 0                 THEN '0 - Sem Atraso'
            WHEN dias_atraso_inicio BETWEEN 1   AND 30  THEN '1 - 1-30 dias'
            WHEN dias_atraso_inicio BETWEEN 31  AND 60  THEN '2 - 31-60 dias'
            WHEN dias_atraso_inicio BETWEEN 61  AND 90  THEN '3 - 61-90 dias'
            WHEN dias_atraso_inicio BETWEEN 91  AND 120 THEN '4 - 91-120 dias'
            WHEN dias_atraso_inicio BETWEEN 121 AND 180 THEN '5 - 121-180 dias'
            ELSE                                            '6 - 181+ dias'
        END AS faixa_atraso_referencia
    FROM evolucao_atraso_contrato
),

metricas_roll_rate AS (
    SELECT
        faixa_atraso_referencia,
        COUNT(*)                                     AS total_observacoes,
        COUNT(DISTINCT id_contrato)                  AS total_contratos_unicos,
        CASE WHEN faixa_atraso_referencia <> '0 - Sem Atraso'
            THEN ROUND(100.0 * AVG(dias_atraso_final = 0), 2) ELSE NULL END AS taxa_cura_percentual,

        -- Métricas de Deterioração (Evento ocorreu em algum momento da janela)
        CASE WHEN faixa_atraso_referencia = '0 - Sem Atraso'
             THEN ROUND(100.0 * AVG(maximo_dias_atraso_na_janela > 0), 2) ELSE NULL END AS taxa_ever_atraso,
        CASE WHEN faixa_atraso_referencia IN ('0 - Sem Atraso', '1 - 1-30 dias')
             THEN ROUND(100.0 * AVG(maximo_dias_atraso_na_janela > 30), 2) ELSE NULL END AS taxa_ever_atraso_30d,
        CASE WHEN faixa_atraso_referencia IN ('0 - Sem Atraso', '1 - 1-30 dias', '2 - 31-60 dias')
             THEN ROUND(100.0 * AVG(maximo_dias_atraso_na_janela > 60), 2) ELSE NULL END AS taxa_ever_atraso_60d,
        CASE WHEN faixa_atraso_referencia IN ('0 - Sem Atraso', '1 - 1-30 dias', '2 - 31-60 dias', '3 - 61-90 dias')
             THEN ROUND(100.0 * AVG(maximo_dias_atraso_na_janela > 90), 2) ELSE NULL END AS taxa_ever_atraso_90d,
        CASE WHEN faixa_atraso_referencia IN ('0 - Sem Atraso', '1 - 1-30 dias', '2 - 31-60 dias', '3 - 61-90 dias', '4 - 91-120 dias')
             THEN ROUND(100.0 * AVG(maximo_dias_atraso_na_janela > 120), 2) ELSE NULL END AS taxa_ever_atraso_120d,
        CASE WHEN faixa_atraso_referencia IN ('0 - Sem Atraso', '1 - 1-30 dias', '2 - 31-60 dias', '3 - 61-90 dias', '4 - 91-120 dias', '5 - 121-180 dias')
             THEN ROUND(100.0 * AVG(maximo_dias_atraso_na_janela > 180), 2) ELSE NULL END AS taxa_ever_atraso_180d,

        -- Métricas de Estado Final (Situação ao término da janela)
        CASE WHEN faixa_atraso_referencia = '0 - Sem Atraso'
             THEN ROUND(100.0 * AVG(dias_atraso_final > 0), 2) ELSE NULL END AS taxa_final_atraso,
        CASE WHEN faixa_atraso_referencia IN ('0 - Sem Atraso', '1 - 1-30 dias')
             THEN ROUND(100.0 * AVG(dias_atraso_final > 30), 2) ELSE NULL END AS taxa_final_atraso_30d,
        CASE WHEN faixa_atraso_referencia IN ('0 - Sem Atraso', '1 - 1-30 dias', '2 - 31-60 dias')
             THEN ROUND(100.0 * AVG(dias_atraso_final > 60), 2) ELSE NULL END AS taxa_final_atraso_60d,
        CASE WHEN faixa_atraso_referencia IN ('0 - Sem Atraso', '1 - 1-30 dias', '2 - 31-60 dias', '3 - 61-90 dias')
             THEN ROUND(100.0 * AVG(dias_atraso_final > 90), 2) ELSE NULL END AS taxa_final_atraso_90d,
        CASE WHEN faixa_atraso_referencia IN ('0 - Sem Atraso', '1 - 1-30 dias', '2 - 31-60 dias', '3 - 61-90 dias', '4 - 91-120 dias')
             THEN ROUND(100.0 * AVG(dias_atraso_final > 120), 2) ELSE NULL END AS taxa_final_atraso_120d,
        CASE WHEN faixa_atraso_referencia IN ('0 - Sem Atraso', '1 - 1-30 dias', '2 - 31-60 dias', '3 - 61-90 dias', '4 - 91-120 dias', '5 - 121-180 dias')
             THEN ROUND(100.0 * AVG(dias_atraso_final > 180), 2) ELSE NULL END AS taxa_final_atraso_180d
FROM base_classificada
    GROUP BY faixa_atraso_referencia
)

SELECT * FROM metricas_roll_rate
ORDER BY faixa_atraso_referencia;

