WITH tb_emprestimos AS (
    SELECT
        id_contrato, id_cliente,
        substr(data_decisao, 1, 10) AS data_ref,
        NULLIF(valor_parcela, 0)    AS parcela_atual
    FROM base_historico_emprestimos
    WHERE status_contrato IN ('Aprovado', 'Recusado')
),

contratos_prev AS (
    SELECT
        e.id_contrato AS id_atual,
        e.data_ref,
        h.id_contrato AS id_contrato_ant,
        h.qtd_parcelas_planejadas AS parcelas_planejadas,
        NULLIF(h.valor_parcela, 0) AS parcela
    FROM tb_emprestimos e
    JOIN base_historico_emprestimos h
      ON h.id_cliente = e.id_cliente
     AND h.status_contrato = 'Aprovado'
     AND h.id_contrato <> e.id_contrato
     AND substr(h.data_decisao, 1, 10) < e.data_ref
     AND h.data_liberacao IS NOT NULL
     AND substr(h.data_liberacao, 1, 10) <= e.data_ref
),

contratos_ativos AS (
    SELECT
        e.id_contrato AS id_atual,
        e.data_ref,
        h.id_contrato AS id_contrato_ant,
        NULLIF(h.valor_credito, 0) AS credito,
        NULLIF(h.valor_parcela, 0) AS parcela,
        julianday(substr(h.data_ultimo_vencimento_original, 1, 10))
          - julianday(e.data_ref)  AS prazo_restante
    FROM tb_emprestimos e
    JOIN base_historico_emprestimos h
      ON h.id_cliente = e.id_cliente
     AND h.status_contrato = 'Aprovado'
     AND h.id_contrato <> e.id_contrato
     AND substr(h.data_decisao, 1, 10) < e.data_ref
     AND h.data_liberacao IS NOT NULL
     AND substr(h.data_liberacao, 1, 10) <= e.data_ref
     AND COALESCE(substr(h.data_encerramento, 1, 10),
                  substr(h.data_ultimo_vencimento_original, 1, 10),
                  '9999-12-31') > e.data_ref
),

-- parcelas dos contratos ativos, com o valor pago até a data_ref
parcelas_ativas AS (
    SELECT
        c.id_atual, c.id_contrato_ant, d.numero_parcela,
        substr(d.data_prevista_pagamento, 1, 10) AS data_prevista,
        c.data_ref,
        d.valor_previsto_parcela AS valor_previsto,
        COALESCE(MAX(g.pago_acum_cap), 0) AS valor_pago
    FROM contratos_ativos c
    JOIN base_dividas d
      ON d.id_contrato = c.id_contrato_ant
     AND COALESCE(d.previsto_invalido, 0) = 0
    LEFT JOIN base_pagamentos g
      ON g.id_contrato = d.id_contrato
     AND g.numero_parcela = d.numero_parcela
     AND substr(g.data_real_pagamento, 1, 10) <= c.data_ref
    GROUP BY c.id_atual, c.id_contrato_ant, d.numero_parcela,
             d.data_prevista_pagamento, c.data_ref, d.valor_previsto_parcela
),

parcelas_status AS (
    SELECT
        *,
        CASE WHEN data_prevista < data_ref THEN 1 ELSE 0 END            AS vencida,
        CASE WHEN valor_pago >= 0.99 * valor_previsto THEN 1 ELSE 0 END AS quitada
    FROM parcelas_ativas
),

resumo_parcelas AS (
    SELECT
        id_atual,
        SUM(CASE WHEN vencida = 1 AND valor_pago > 0 AND quitada = 0 THEN 1 ELSE 0 END)
                                                                  AS qtd_pagamentos_parciais,
        SUM(CASE WHEN vencida = 1 THEN valor_pago ELSE 0 END)     AS soma_pago_vencidas,
        SUM(CASE WHEN vencida = 1 THEN valor_previsto ELSE 0 END) AS soma_previsto_vencidas,
        SUM(CASE WHEN vencida = 1 AND quitada = 0 THEN valor_previsto ELSE 0 END)
                                                                  AS valor_em_atraso,
        SUM(CASE WHEN vencida = 1 AND quitada = 0 THEN 1 ELSE 0 END)
                                                                  AS qtd_parcelas_em_atraso,
        SUM(CASE WHEN quitada = 0 THEN valor_previsto ELSE 0 END) AS exposicao_total,
        SUM(CASE WHEN vencida = 1 AND quitada = 0 THEN valor_previsto - valor_pago ELSE 0 END)
                                                                  AS saldo_vencido,
        SUM(CASE WHEN quitada = 0 THEN valor_previsto - valor_pago ELSE 0 END)
                                                                  AS saldo_conhecido
    FROM parcelas_status
    GROUP BY id_atual
),

resumo_contratos AS (
    SELECT
        id_atual,
        COUNT(*)            AS qtd_contratos_ativos,
        SUM(credito)        AS credito_aberto,
        SUM(parcela)        AS parcela_aberta,
        MAX(credito)        AS maior_credito_aberto,
        AVG(credito)        AS credito_medio_aberto,
        AVG(prazo_restante) AS prazo_restante_medio
    FROM contratos_ativos
    GROUP BY id_atual
),

parcelas_historico AS (
    SELECT
        cp.id_atual,
        cp.data_ref,
        d.id_contrato AS id_contrato_ant,
        d.numero_parcela,
        substr(d.data_prevista_pagamento, 1, 10) AS data_prevista,
        d.valor_previsto_parcela                 AS valor_previsto,
        MIN(CASE WHEN g.pago_acum_cap >= 0.99 * d.valor_previsto_parcela
                 THEN substr(g.data_real_pagamento, 1, 10) END) AS data_quitacao_ref,
        MAX(CASE WHEN g.valor_pago_parcela > 0
                 THEN substr(g.data_real_pagamento, 1, 10) END) AS data_ultimo_pagamento_ref,
        COALESCE(MAX(g.pago_acum_cap), 0)        AS valor_pago_ref
    FROM contratos_prev cp
    JOIN base_dividas d
      ON d.id_contrato = cp.id_contrato_ant
     AND COALESCE(d.previsto_invalido, 0) = 0
    LEFT JOIN base_pagamentos g
      ON g.id_contrato = d.id_contrato
     AND g.numero_parcela = d.numero_parcela
     AND substr(g.data_real_pagamento, 1, 10) <= cp.data_ref
    GROUP BY cp.id_atual, cp.data_ref, d.id_contrato, d.numero_parcela,
             d.data_prevista_pagamento, d.valor_previsto_parcela
),

resumo_ultimo_pagamento AS (
    SELECT
        id_atual,
        data_ref,
        MAX(data_ultimo_pagamento_ref) AS data_ultimo_pagamento
    FROM parcelas_historico
    GROUP BY id_atual, data_ref
),

parcelas_hist AS (
    SELECT
        *,
        CASE WHEN data_prevista < data_ref THEN 1 ELSE 0 END      AS vencida,
        CASE WHEN data_quitacao_ref IS NOT NULL THEN 1 ELSE 0 END AS quitada_ref,
        julianday(COALESCE(data_quitacao_ref, data_ref))
          - julianday(data_prevista)                              AS dias_diff
    FROM parcelas_historico
    WHERE data_prevista < data_ref OR data_quitacao_ref IS NOT NULL
),

parcelas_ordenadas AS (
    SELECT
        id_atual,
        CASE WHEN quitada_ref = 1 AND dias_diff <= 0 THEN 1 ELSE 0 END AS em_dia,
        ROW_NUMBER() OVER (PARTITION BY id_atual
                           ORDER BY data_prevista DESC,
                                    id_contrato_ant DESC,
                                    numero_parcela DESC) AS rn
    FROM parcelas_hist
    WHERE vencida = 1
),

resumo_streak AS (
    SELECT
        id_atual,
        COALESCE(MIN(CASE WHEN em_dia = 0 THEN rn END) - 1, COUNT(*)) AS streak_em_dia
    FROM parcelas_ordenadas
    GROUP BY id_atual
),

resumo_comportamento AS (
    SELECT
        id_atual,
        AVG(CASE WHEN quitada_ref = 1 THEN MAX(0, dias_diff) END)    AS atraso_pago_medio,
        AVG(CASE WHEN quitada_ref = 1 THEN MAX(-60, -dias_diff) END) AS dias_antecipacao_medio,
        1.0 * SUM(CASE WHEN quitada_ref = 1 AND dias_diff < 0 THEN 1 ELSE 0 END)
            / NULLIF(SUM(quitada_ref), 0)                            AS pct_pagas_antecipadas,
        1.0 * SUM(CASE WHEN vencida = 1 AND dias_diff > 0 THEN valor_previsto ELSE 0 END)
            / NULLIF(SUM(CASE WHEN vencida = 1 THEN valor_previsto ELSE 0 END), 0)
                                                                     AS pct_atraso_ponderado_valor,
        1.0 * SUM(CASE WHEN vencida = 1 AND valor_pago_ref > 0 AND quitada_ref = 0
                       THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN valor_pago_ref > 0 THEN 1 ELSE 0 END), 0)
                                                                     AS pct_pagamentos_parciais,
        AVG(CASE WHEN vencida = 1 AND data_prevista >= date(data_ref, '-3 months')
                 THEN MAX(0, dias_diff) END)                         AS atraso_medio_3m,
        AVG(CASE WHEN vencida = 1 AND data_prevista >= date(data_ref, '-6 months')
                 THEN MAX(0, dias_diff) END)                         AS atraso_medio_6m,
        AVG(CASE WHEN vencida = 1 AND data_prevista >= date(data_ref, '-12 months')
                 THEN MAX(0, dias_diff) END)                         AS atraso_medio_12m,
        AVG(CASE WHEN vencida = 1 THEN MAX(0, dias_diff) END)        AS atraso_medio_vida
    FROM parcelas_hist
    GROUP BY id_atual
),

-- por contrato anterior: teve parcela com >= 30 dias de atraso? tem parcela vencida e não paga?
contratos_atraso AS (
    SELECT
        id_atual,
        id_contrato_ant,
        MAX(CASE WHEN dias_diff >= 30 THEN 1 ELSE 0 END) AS teve_atraso_30d,
        MAX(CASE WHEN quitada_ref = 0 THEN 1 ELSE 0 END) AS teve_atraso_aberto
    FROM parcelas_hist
    WHERE vencida = 1
    GROUP BY id_atual, id_contrato_ant
),

resumo_atraso30 AS (
    SELECT
        id_atual,
        SUM(teve_atraso_30d)    AS qtd_contratos_com_atraso_30d,
        SUM(teve_atraso_aberto) AS qtd_contratos_com_atraso_aberto,
        COUNT(*)                AS qtd_contratos_com_parcela_vencida
    FROM contratos_atraso
    GROUP BY id_atual
),

quitadas_contrato AS (
    SELECT
        id_atual,
        id_contrato_ant,
        SUM(CASE WHEN data_quitacao_ref IS NOT NULL THEN 1 ELSE 0 END) AS qtd_quitadas,
        SUM(CASE WHEN data_prevista < data_ref AND data_quitacao_ref IS NULL
                 THEN 1 ELSE 0 END)                                    AS qtd_vencidas_abertas
    FROM parcelas_historico
    GROUP BY id_atual, id_contrato_ant
),

contratos_estimado AS (
    SELECT
        cp.id_atual,
        cp.id_contrato_ant,
        cp.parcela,
        CASE WHEN cp.parcelas_planejadas IS NULL THEN NULL
             ELSE MAX(0, cp.parcelas_planejadas - COALESCE(q.qtd_quitadas, 0)) END
                                                  AS parcelas_restantes,
        COALESCE(q.qtd_vencidas_abertas, 0)       AS qtd_vencidas_abertas
    FROM contratos_prev cp
    LEFT JOIN quitadas_contrato q
      ON q.id_atual = cp.id_atual
     AND q.id_contrato_ant = cp.id_contrato_ant
),

resumo_estimado AS (
    SELECT
        id_atual,
        SUM(CASE WHEN COALESCE(parcelas_restantes, 0) > 0 OR qtd_vencidas_abertas > 0
                 THEN 1 ELSE 0 END)               AS qtd_contratos_ativos_estimado,
        SUM(parcelas_restantes)                   AS parcelas_restantes_estimadas,
        SUM(parcelas_restantes * parcela)         AS saldo_a_vencer_estimado
    FROM contratos_estimado
    GROUP BY id_atual
),

tb_features AS (
    SELECT
        e.data_ref, e.id_contrato, e.id_cliente, 

        COALESCE(rc.qtd_contratos_ativos, 0)     AS qtd_contratos_ativos,

        COALESCE(rp.qtd_pagamentos_parciais, 0)  AS qtd_pagamentos_parciais,
        1.0 * rp.soma_pago_vencidas / NULLIF(rp.soma_previsto_vencidas, 0)
                                                AS razao_pago_previsto,
        COALESCE(rp.valor_em_atraso, 0)          AS valor_em_atraso,

        CASE WHEN rp.id_atual IS NULL    THEN NULL
            WHEN rp.exposicao_total = 0 THEN 0
            ELSE 1.0 * rp.valor_em_atraso / rp.exposicao_total END
                                                AS pct_exposicao_vencida,

        1.0 * CASE WHEN rc.qtd_contratos_ativos IS NULL THEN 0 ELSE rc.credito_aberto END
            / NULLIF(c.renda_anual, 0)           AS credito_aberto_sobre_renda,
        1.0 * CASE WHEN rc.qtd_contratos_ativos IS NULL THEN 0 ELSE rc.parcela_aberta END
            / NULLIF(c.renda_anual / 12.0, 0)    AS parcela_aberta_sobre_renda,

        1.0 * e.parcela_atual / NULLIF(rc.parcela_aberta, 0)
                                                AS nova_parcela_sobre_comprometimento_anterior,
        1.0 * rc.maior_credito_aberto / NULLIF(rc.credito_aberto, 0)
                                                AS pct_credito_no_maior_contrato,
        rc.credito_medio_aberto                  AS credito_medio_por_contrato_aberto,
        rc.prazo_restante_medio                  AS prazo_restante_medio_aberto,
        rs.streak_em_dia                         AS streak_em_dia,

        rcomp.atraso_pago_medio                  AS atraso_pago_medio,
        rcomp.dias_antecipacao_medio             AS dias_antecipacao_medio,
        rcomp.pct_pagas_antecipadas              AS pct_pagas_antecipadas,
        rcomp.pct_atraso_ponderado_valor         AS pct_atraso_ponderado_valor,
        COALESCE(ra.qtd_contratos_com_atraso_30d, 0) AS qtd_contratos_com_atraso_30d,
        1.0 * ra.qtd_contratos_com_atraso_30d
            / NULLIF(ra.qtd_contratos_com_parcela_vencida, 0)
                                                AS pct_contratos_com_atraso_30d,

        julianday(e.data_ref) - julianday(ru.data_ultimo_pagamento)
                                                AS dias_desde_ultimo_pagamento,
        rcomp.pct_pagamentos_parciais            AS pct_pagamentos_parciais,
        rcomp.atraso_medio_3m                    AS atraso_medio_3m,
        rcomp.atraso_medio_6m                    AS atraso_medio_6m,
        rcomp.atraso_medio_12m                   AS atraso_medio_12m,
        rcomp.atraso_medio_vida                  AS atraso_medio_vida,
        COALESCE(rp.qtd_parcelas_em_atraso, 0)   AS qtd_parcelas_em_atraso,

        CASE WHEN rp.id_atual IS NULL        THEN NULL
            WHEN rp.saldo_conhecido <= 0    THEN 0
            ELSE 1.0 * rp.saldo_vencido / rp.saldo_conhecido END
                                                AS pct_saldo_vencido,
        COALESCE(ra.qtd_contratos_com_atraso_aberto, 0)
                                                AS qtd_contratos_com_atraso_aberto,
        COALESCE(re.qtd_contratos_ativos_estimado, 0)
                                                AS qtd_contratos_ativos_estimado,
        CASE WHEN re.id_atual IS NULL THEN 0 ELSE re.parcelas_restantes_estimadas END
                                                AS parcelas_restantes_estimadas,
        CASE WHEN re.id_atual IS NULL THEN 0 ELSE re.saldo_a_vencer_estimado END
                                                AS saldo_a_vencer_estimado,
        CASE WHEN rc.qtd_contratos_ativos IS NULL THEN 0 ELSE rc.parcela_aberta END
                                                AS parcela_mensal_aberta
    FROM tb_emprestimos e
    LEFT JOIN base_cadastral c              ON c.id_cliente = e.id_cliente
    LEFT JOIN resumo_parcelas rp            ON rp.id_atual  = e.id_contrato
    LEFT JOIN resumo_contratos rc           ON rc.id_atual  = e.id_contrato
    LEFT JOIN resumo_streak rs              ON rs.id_atual  = e.id_contrato
    LEFT JOIN resumo_comportamento rcomp    ON rcomp.id_atual = e.id_contrato
    LEFT JOIN resumo_atraso30 ra            ON ra.id_atual  = e.id_contrato
    LEFT JOIN resumo_ultimo_pagamento ru    ON ru.id_atual  = e.id_contrato
    LEFT JOIN resumo_estimado re            ON re.id_atual  = e.id_contrato
)

SELECT  
        data_ref, 
        id_contrato, 
        id_cliente, 
        qtd_contratos_ativos,
        qtd_pagamentos_parciais,
        razao_pago_previsto,
        valor_em_atraso,
        pct_exposicao_vencida,
        credito_aberto_sobre_renda,
        parcela_aberta_sobre_renda,
        nova_parcela_sobre_comprometimento_anterior,
        pct_credito_no_maior_contrato,
        credito_medio_por_contrato_aberto,
        prazo_restante_medio_aberto,
        streak_em_dia,
        atraso_pago_medio,
        dias_antecipacao_medio,
        pct_pagas_antecipadas,
        pct_atraso_ponderado_valor,
        qtd_contratos_com_atraso_30d,
        pct_contratos_com_atraso_30d,
        dias_desde_ultimo_pagamento,
        pct_pagamentos_parciais,
        atraso_medio_3m,
        atraso_medio_6m,
        atraso_medio_12m,
        atraso_medio_vida,
        qtd_parcelas_em_atraso,
        pct_saldo_vencido,
        qtd_contratos_com_atraso_aberto,
        qtd_contratos_ativos_estimado,
        parcelas_restantes_estimadas,
        saldo_a_vencer_estimado,
        parcela_mensal_aberta

       
FROM tb_features