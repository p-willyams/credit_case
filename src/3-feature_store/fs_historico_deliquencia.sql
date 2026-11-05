
WITH tb_emprestimos AS (
    SELECT
        id_contrato, id_cliente,
        substr(data_decisao, 1, 10) AS data_ref
    FROM base_historico_emprestimos
    WHERE status_contrato IN ('Aprovado', 'Recusado')
),
 
-- parcelas de contratos anteriores aprovados do cliente, já vencidas na data_ref
parcelas_vencidas AS (
    SELECT
        e.id_contrato AS id_atual,
        e.data_ref,
        d.id_contrato AS id_contrato_ant,
        d.numero_parcela,
        substr(d.data_prevista_pagamento, 1, 10) AS data_prevista,
        d.valor_previsto_parcela                 AS valor_previsto
    FROM tb_emprestimos e
    JOIN base_historico_emprestimos h
      ON h.id_cliente = e.id_cliente
     AND h.status_contrato = 'Aprovado'
     AND h.id_contrato <> e.id_contrato
     AND substr(h.data_decisao, 1, 10) < e.data_ref
    JOIN base_dividas d
      ON d.id_contrato = h.id_contrato
     AND COALESCE(d.previsto_invalido, 0) = 0
     AND substr(d.data_prevista_pagamento, 1, 10) < e.data_ref  
),
 
-- data de quitação olhando só pagamentos até a data_ref
-- (NULL = ainda não quitada na data_ref)
parcelas_quitacao AS (
    SELECT
        v.id_atual, v.id_contrato_ant, v.numero_parcela,
        v.data_ref, v.data_prevista,
        MIN(substr(g.data_real_pagamento, 1, 10)) AS data_quitacao_asof
    FROM parcelas_vencidas v
    LEFT JOIN base_pagamentos g
      ON g.id_contrato = v.id_contrato_ant
     AND g.numero_parcela = v.numero_parcela
     AND substr(g.data_real_pagamento, 1, 10) <= v.data_ref
     AND g.pago_acum >= 0.99 * v.valor_previsto
    GROUP BY v.id_atual, v.id_contrato_ant, v.numero_parcela, v.data_ref, v.data_prevista
),
 
parcelas_atraso AS (
    SELECT
        id_atual, id_contrato_ant, numero_parcela, data_prevista,
        CASE WHEN data_quitacao_asof IS NULL THEN 1 ELSE 0 END AS em_aberto,
        CAST(julianday(data_ref) - julianday(data_prevista) AS INTEGER) AS dias_desde_vcto,
        CAST(julianday(COALESCE(data_quitacao_asof, data_ref))
             - julianday(data_prevista) AS INTEGER) AS dias_atraso,
        CASE WHEN data_prevista >= date(data_ref, '-3 months')  THEN 1 ELSE 0 END AS dentro_3m,
        CASE WHEN data_prevista >= date(data_ref, '-6 months')  THEN 1 ELSE 0 END AS dentro_6m,
        CASE WHEN data_prevista >= date(data_ref, '-12 months') THEN 1 ELSE 0 END AS dentro_12m
    FROM parcelas_quitacao
),
 
parcelas_atraso_rank AS (
    SELECT
        *,
        MAX(dias_atraso, 0) AS dias_atraso_pos,
        ROW_NUMBER() OVER (PARTITION BY id_atual
                           ORDER BY dias_atraso DESC, data_prevista DESC,
                                    id_contrato_ant DESC, numero_parcela DESC) AS rn_maior_atraso,
        ROW_NUMBER() OVER (PARTITION BY id_atual
                           ORDER BY data_prevista DESC,
                                    id_contrato_ant DESC, numero_parcela DESC) AS rn_ultima_parcela
    FROM parcelas_atraso
),
 
-- contrato anterior aprovado mais recente (mesmo critério do 'ordem = 1' da query de valores)
ultimo_contrato AS (
    SELECT id_atual, id_contrato_ant
    FROM (
        SELECT
            e.id_contrato AS id_atual,
            h.id_contrato AS id_contrato_ant,
            ROW_NUMBER() OVER (PARTITION BY e.id_contrato
                               ORDER BY substr(h.data_decisao, 1, 10) DESC, h.id_contrato DESC) AS ordem
        FROM tb_emprestimos e
        JOIN base_historico_emprestimos h
          ON h.id_cliente = e.id_cliente
         AND h.status_contrato = 'Aprovado'
         AND h.id_contrato <> e.id_contrato
         AND substr(h.data_decisao, 1, 10) < e.data_ref
    )
    WHERE ordem = 1
),
 
-- maior atraso entre as parcelas vencidas desse contrato (NULL se ainda não tinha parcela vencida)
atraso_ultimo_contrato AS (
    SELECT u.id_atual, MAX(p.dias_atraso_pos) AS atraso_max_ultimo_contrato
    FROM ultimo_contrato u
    JOIN parcelas_atraso_rank p
      ON p.id_atual = u.id_atual
     AND p.id_contrato_ant = u.id_contrato_ant
    GROUP BY u.id_atual
),
 
resumo AS (
    SELECT
        id_atual,
        
        SUM(CASE WHEN 1 = 1 THEN 1 ELSE 0 END) AS qtd_parcelas_vencidas_vida,
        SUM(CASE WHEN dias_atraso > 0 THEN 1 ELSE 0 END) AS qtd_parcelas_atrasadas_vida,
        SUM(CASE WHEN dias_atraso > 5 THEN 1 ELSE 0 END) AS qtd_atraso_5d_vida,
        SUM(CASE WHEN dias_atraso > 15 THEN 1 ELSE 0 END) AS qtd_atraso_15d_vida,
        SUM(CASE WHEN dias_atraso > 30 THEN 1 ELSE 0 END) AS qtd_atraso_30d_vida,
        SUM(CASE WHEN dias_atraso > 60 THEN 1 ELSE 0 END) AS qtd_atraso_60d_vida,
        SUM(CASE WHEN dias_atraso > 90 THEN 1 ELSE 0 END) AS qtd_atraso_90d_vida,
        SUM(CASE WHEN dias_atraso > 120 THEN 1 ELSE 0 END) AS qtd_atraso_maior_120d_vida,
        SUM(CASE WHEN dentro_3m = 1 THEN 1 ELSE 0 END) AS qtd_parcelas_vencidas_3m,
        SUM(CASE WHEN dentro_3m = 1 AND dias_atraso > 0 THEN 1 ELSE 0 END) AS qtd_parcelas_atrasadas_3m,
        SUM(CASE WHEN dentro_3m = 1 AND dias_atraso > 5 THEN 1 ELSE 0 END) AS qtd_atraso_5d_3m,
        SUM(CASE WHEN dentro_3m = 1 AND dias_atraso > 15 THEN 1 ELSE 0 END) AS qtd_atraso_15d_3m,
        SUM(CASE WHEN dentro_3m = 1 AND dias_atraso > 30 THEN 1 ELSE 0 END) AS qtd_atraso_30d_3m,
        SUM(CASE WHEN dentro_3m = 1 AND dias_atraso > 60 THEN 1 ELSE 0 END) AS qtd_atraso_60d_3m,
        SUM(CASE WHEN dentro_3m = 1 AND dias_atraso > 90 THEN 1 ELSE 0 END) AS qtd_atraso_90d_3m,
        SUM(CASE WHEN dentro_3m = 1 AND dias_atraso > 120 THEN 1 ELSE 0 END) AS qtd_atraso_maior_120d_3m,
        SUM(CASE WHEN dentro_6m = 1 THEN 1 ELSE 0 END) AS qtd_parcelas_vencidas_6m,
        SUM(CASE WHEN dentro_6m = 1 AND dias_atraso > 0 THEN 1 ELSE 0 END) AS qtd_parcelas_atrasadas_6m,
        SUM(CASE WHEN dentro_6m = 1 AND dias_atraso > 5 THEN 1 ELSE 0 END) AS qtd_atraso_5d_6m,
        SUM(CASE WHEN dentro_6m = 1 AND dias_atraso > 15 THEN 1 ELSE 0 END) AS qtd_atraso_15d_6m,
        SUM(CASE WHEN dentro_6m = 1 AND dias_atraso > 30 THEN 1 ELSE 0 END) AS qtd_atraso_30d_6m,
        SUM(CASE WHEN dentro_6m = 1 AND dias_atraso > 60 THEN 1 ELSE 0 END) AS qtd_atraso_60d_6m,
        SUM(CASE WHEN dentro_6m = 1 AND dias_atraso > 90 THEN 1 ELSE 0 END) AS qtd_atraso_90d_6m,
        SUM(CASE WHEN dentro_6m = 1 AND dias_atraso > 120 THEN 1 ELSE 0 END) AS qtd_atraso_maior_120d_6m,
        SUM(CASE WHEN dentro_12m = 1 THEN 1 ELSE 0 END) AS qtd_parcelas_vencidas_12m,
        SUM(CASE WHEN dentro_12m = 1 AND dias_atraso > 0 THEN 1 ELSE 0 END) AS qtd_parcelas_atrasadas_12m,
        SUM(CASE WHEN dentro_12m = 1 AND dias_atraso > 5 THEN 1 ELSE 0 END) AS qtd_atraso_5d_12m,
        SUM(CASE WHEN dentro_12m = 1 AND dias_atraso > 15 THEN 1 ELSE 0 END) AS qtd_atraso_15d_12m,
        SUM(CASE WHEN dentro_12m = 1 AND dias_atraso > 30 THEN 1 ELSE 0 END) AS qtd_atraso_30d_12m,
        SUM(CASE WHEN dentro_12m = 1 AND dias_atraso > 60 THEN 1 ELSE 0 END) AS qtd_atraso_60d_12m,
        SUM(CASE WHEN dentro_12m = 1 AND dias_atraso > 90 THEN 1 ELSE 0 END) AS qtd_atraso_90d_12m,
        SUM(CASE WHEN dentro_12m = 1 AND dias_atraso > 120 THEN 1 ELSE 0 END) AS qtd_atraso_maior_120d_12m,
 
        AVG(CASE WHEN dentro_3m = 1  THEN dias_atraso_pos END) AS atraso_medio_3m,
        AVG(CASE WHEN dentro_12m = 1 THEN dias_atraso_pos END) AS atraso_medio_12m,
 
        AVG(dias_atraso_pos)                               AS atraso_medio,
        MAX(dias_atraso_pos)                               AS atraso_max,
 
        MAX(CASE WHEN rn_maior_atraso = 1 AND dias_atraso > 0
                 THEN dias_desde_vcto END)                 AS dias_max_atraso,
 
        MAX(CASE WHEN rn_ultima_parcela = 1
                 THEN dias_atraso_pos END)                 AS atraso_ultima_parcela,
 

        MIN(CASE WHEN dias_atraso > 0   THEN dias_desde_vcto END) AS dias_desde_ultimo_atraso_maior_0d,
        MIN(CASE WHEN dias_atraso > 30  THEN dias_desde_vcto END) AS dias_desde_ultimo_atraso_maior_30d,
        MIN(CASE WHEN dias_atraso > 60  THEN dias_desde_vcto END) AS dias_desde_ultimo_atraso_maior_60d,
        MIN(CASE WHEN dias_atraso > 90  THEN dias_desde_vcto END) AS dias_desde_ultimo_atraso_maior_90d,
        MIN(CASE WHEN dias_atraso > 120 THEN dias_desde_vcto END) AS dias_desde_ultimo_atraso_maior_120d,
 
        COALESCE(MAX(CASE WHEN em_aberto = 1
                          THEN dias_atraso_pos END), 0)    AS dpd_atual_max,
 
        MAX(CASE WHEN dias_atraso >= 30 THEN 1 ELSE 0 END) AS flag_ever_30d,
        MAX(CASE WHEN dias_atraso >= 60 THEN 1 ELSE 0 END) AS flag_ever_60d,
        MAX(CASE WHEN dias_atraso >= 90 THEN 1 ELSE 0 END) AS flag_ever_90d
    FROM parcelas_atraso_rank
    GROUP BY id_atual
)
 
SELECT
    e.data_ref, e.id_contrato, e.id_cliente,

    COALESCE(r.qtd_parcelas_vencidas_vida, 0) AS qtd_parcelas_vencidas_vida,
    COALESCE(r.qtd_parcelas_atrasadas_vida, 0) AS qtd_parcelas_atrasadas_vida,
    COALESCE(r.qtd_atraso_5d_vida, 0) AS qtd_atraso_5d_vida,
    COALESCE(r.qtd_atraso_15d_vida, 0) AS qtd_atraso_15d_vida,
    COALESCE(r.qtd_atraso_30d_vida, 0) AS qtd_atraso_30d_vida,
    COALESCE(r.qtd_atraso_60d_vida, 0) AS qtd_atraso_60d_vida,
    COALESCE(r.qtd_atraso_90d_vida, 0) AS qtd_atraso_90d_vida,
    COALESCE(r.qtd_atraso_maior_120d_vida, 0) AS qtd_atraso_maior_120d_vida,
 
    COALESCE(r.qtd_parcelas_vencidas_3m, 0) AS qtd_parcelas_vencidas_3m,
    COALESCE(r.qtd_parcelas_atrasadas_3m, 0) AS qtd_parcelas_atrasadas_3m,
    COALESCE(r.qtd_atraso_5d_3m, 0) AS qtd_atraso_5d_3m,
    COALESCE(r.qtd_atraso_15d_3m, 0) AS qtd_atraso_15d_3m,
    COALESCE(r.qtd_atraso_30d_3m, 0) AS qtd_atraso_30d_3m,
    COALESCE(r.qtd_atraso_60d_3m, 0) AS qtd_atraso_60d_3m,
    COALESCE(r.qtd_atraso_90d_3m, 0) AS qtd_atraso_90d_3m,
    COALESCE(r.qtd_atraso_maior_120d_3m, 0) AS qtd_atraso_maior_120d_3m,
 
    COALESCE(r.qtd_parcelas_vencidas_6m, 0) AS qtd_parcelas_vencidas_6m,
    COALESCE(r.qtd_parcelas_atrasadas_6m, 0) AS qtd_parcelas_atrasadas_6m,
    COALESCE(r.qtd_atraso_5d_6m, 0) AS qtd_atraso_5d_6m,
    COALESCE(r.qtd_atraso_15d_6m, 0) AS qtd_atraso_15d_6m,
    COALESCE(r.qtd_atraso_30d_6m, 0) AS qtd_atraso_30d_6m,
    COALESCE(r.qtd_atraso_60d_6m, 0) AS qtd_atraso_60d_6m,
    COALESCE(r.qtd_atraso_90d_6m, 0) AS qtd_atraso_90d_6m,
    COALESCE(r.qtd_atraso_maior_120d_6m, 0) AS qtd_atraso_maior_120d_6m,
 
    COALESCE(r.qtd_parcelas_vencidas_12m, 0) AS qtd_parcelas_vencidas_12m,
    COALESCE(r.qtd_parcelas_atrasadas_12m, 0) AS qtd_parcelas_atrasadas_12m,
    COALESCE(r.qtd_atraso_5d_12m, 0) AS qtd_atraso_5d_12m,
    COALESCE(r.qtd_atraso_15d_12m, 0) AS qtd_atraso_15d_12m,
    COALESCE(r.qtd_atraso_30d_12m, 0) AS qtd_atraso_30d_12m,
    COALESCE(r.qtd_atraso_60d_12m, 0) AS qtd_atraso_60d_12m,
    COALESCE(r.qtd_atraso_90d_12m, 0) AS qtd_atraso_90d_12m,
    COALESCE(r.qtd_atraso_maior_120d_12m, 0) AS qtd_atraso_maior_120d_12m,
 
    1.0 * r.qtd_parcelas_atrasadas_vida / r.qtd_parcelas_vencidas_vida AS pct_parcelas_atrasadas_vida,
    1.0 * r.qtd_atraso_5d_vida / r.qtd_parcelas_vencidas_vida AS pct_atraso_5d_vida,
    1.0 * r.qtd_atraso_15d_vida / r.qtd_parcelas_vencidas_vida AS pct_atraso_15d_vida,
    1.0 * r.qtd_atraso_30d_vida / r.qtd_parcelas_vencidas_vida AS pct_atraso_30d_vida,
    1.0 * r.qtd_atraso_60d_vida / r.qtd_parcelas_vencidas_vida AS pct_atraso_60d_vida,
    1.0 * r.qtd_atraso_90d_vida / r.qtd_parcelas_vencidas_vida AS pct_atraso_90d_vida,
    1.0 * r.qtd_atraso_maior_120d_vida / r.qtd_parcelas_vencidas_vida AS pct_atraso_maior_120d_vida,
 
    1.0 * r.qtd_parcelas_atrasadas_3m / r.qtd_parcelas_vencidas_3m AS pct_parcelas_atrasadas_3m,
    1.0 * r.qtd_atraso_5d_3m / r.qtd_parcelas_vencidas_3m AS pct_atraso_5d_3m,
    1.0 * r.qtd_atraso_15d_3m / r.qtd_parcelas_vencidas_3m AS pct_atraso_15d_3m,
    1.0 * r.qtd_atraso_30d_3m / r.qtd_parcelas_vencidas_3m AS pct_atraso_30d_3m,
    1.0 * r.qtd_atraso_60d_3m / r.qtd_parcelas_vencidas_3m AS pct_atraso_60d_3m,
    1.0 * r.qtd_atraso_90d_3m / r.qtd_parcelas_vencidas_3m AS pct_atraso_90d_3m,
    1.0 * r.qtd_atraso_maior_120d_3m / r.qtd_parcelas_vencidas_3m AS pct_atraso_maior_120d_3m,
 
    1.0 * r.qtd_parcelas_atrasadas_6m / r.qtd_parcelas_vencidas_6m AS pct_parcelas_atrasadas_6m,
    1.0 * r.qtd_atraso_5d_6m / r.qtd_parcelas_vencidas_6m AS pct_atraso_5d_6m,
    1.0 * r.qtd_atraso_15d_6m / r.qtd_parcelas_vencidas_6m AS pct_atraso_15d_6m,
    1.0 * r.qtd_atraso_30d_6m / r.qtd_parcelas_vencidas_6m AS pct_atraso_30d_6m,
    1.0 * r.qtd_atraso_60d_6m / r.qtd_parcelas_vencidas_6m AS pct_atraso_60d_6m,
    1.0 * r.qtd_atraso_90d_6m / r.qtd_parcelas_vencidas_6m AS pct_atraso_90d_6m,
    1.0 * r.qtd_atraso_maior_120d_6m / r.qtd_parcelas_vencidas_6m AS pct_atraso_maior_120d_6m,
 
    1.0 * r.qtd_parcelas_atrasadas_12m / r.qtd_parcelas_vencidas_12m AS pct_parcelas_atrasadas_12m,
    1.0 * r.qtd_atraso_5d_12m / r.qtd_parcelas_vencidas_12m AS pct_atraso_5d_12m,
    1.0 * r.qtd_atraso_15d_12m / r.qtd_parcelas_vencidas_12m AS pct_atraso_15d_12m,
    1.0 * r.qtd_atraso_30d_12m / r.qtd_parcelas_vencidas_12m AS pct_atraso_30d_12m,
    1.0 * r.qtd_atraso_60d_12m / r.qtd_parcelas_vencidas_12m AS pct_atraso_60d_12m,
    1.0 * r.qtd_atraso_90d_12m / r.qtd_parcelas_vencidas_12m AS pct_atraso_90d_12m,
    1.0 * r.qtd_atraso_maior_120d_12m / r.qtd_parcelas_vencidas_12m AS pct_atraso_maior_120d_12m,
 
    r.atraso_medio,
    r.atraso_max,
    r.dias_max_atraso,
    r.atraso_ultima_parcela,
    r.dias_desde_ultimo_atraso_maior_0d,
    r.dias_desde_ultimo_atraso_maior_30d,
    r.dias_desde_ultimo_atraso_maior_60d,
    r.dias_desde_ultimo_atraso_maior_90d,
    r.dias_desde_ultimo_atraso_maior_120d,
    r.dpd_atual_max,
 

    r.atraso_medio_3m - r.atraso_medio_12m AS tendencia_atraso,
 
    u.atraso_max_ultimo_contrato,
 
    COALESCE(r.flag_ever_30d, 0) AS flag_ever_30d,
    COALESCE(r.flag_ever_60d, 0) AS flag_ever_60d,
    COALESCE(r.flag_ever_90d, 0) AS flag_ever_90d
FROM tb_emprestimos e
LEFT JOIN resumo r                 ON r.id_atual = e.id_contrato
LEFT JOIN atraso_ultimo_contrato u ON u.id_atual = e.id_contrato;