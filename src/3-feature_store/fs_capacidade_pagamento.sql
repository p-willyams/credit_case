WITH atual AS (
    SELECT id_contrato, id_cliente,
           substr(data_decisao, 1, 10)  AS data_ref,
           status_contrato,                                 
           NULLIF(valor_parcela, 0)     AS valor_parcela_atual,
           NULLIF(valor_solicitado, 0)  AS valor_credito_atual
    FROM base_historico_emprestimos
    WHERE status_contrato = 'Aprovado' OR status_contrato = 'Recusado'
),

anteriores AS (                                
    SELECT a.id_contrato AS id_atual, a.data_ref,
           h.id_contrato AS id_ant,
           h.qtd_parcelas_planejadas      AS prazo,
           NULLIF(h.valor_parcela, 0)     AS valor_parcela,
           NULLIF(h.valor_solicitado, 0)  AS valor_solicitado
    FROM atual a
    JOIN base_historico_emprestimos h
      ON h.id_cliente = a.id_cliente
     AND h.status_contrato = 'Aprovado'
     AND h.id_contrato <> a.id_contrato
     AND substr(h.data_decisao, 1, 10) < a.data_ref
),

situacao AS (                                    
    SELECT an.id_atual, an.id_ant, an.prazo, an.valor_parcela,
           SUM(CASE WHEN d.data_quitacao IS NOT NULL
                     AND date(d.data_quitacao) <= an.data_ref THEN 1 ELSE 0 END) AS qtd_quitadas,
           SUM(CASE WHEN date(d.data_prevista_pagamento) < an.data_ref
                     AND (d.data_quitacao IS NULL OR date(d.data_quitacao) > an.data_ref)
                    THEN 1 ELSE 0 END)                                            AS qtd_vencidas_abertas
    FROM anteriores an
    JOIN base_dividas d
      ON d.id_contrato = an.id_ant
     AND COALESCE(d.previsto_invalido, 0) = 0
    GROUP BY an.id_atual, an.id_ant, an.prazo, an.valor_parcela
),

abertos AS (
    SELECT *,
           CASE WHEN prazo > 0 THEN MAX(prazo - qtd_quitadas, 0)
                ELSE qtd_vencidas_abertas END                                     AS parcelas_restantes,
           CASE WHEN prazo > 0 AND valor_parcela IS NOT NULL THEN 0 ELSE 1 END    AS incompleto
    FROM situacao
),

exposicao AS (
    SELECT id_atual,
           COUNT(*)                                AS qtd_contratos_abertos,
           SUM(valor_parcela)                      AS parcela_mensal_aberta,
           SUM(parcelas_restantes * valor_parcela) AS saldo_aberto_estimado,
           MAX(incompleto)                         AS carteira_incompleta
    FROM abertos
    WHERE parcelas_restantes > 0
    GROUP BY id_atual
),

medias AS (
    SELECT id_atual,
           COUNT(*)              AS qtd_contratos_anteriores,
           AVG(valor_solicitado) AS media_credito_historico,
           AVG(valor_parcela)    AS media_parcela_historica
    FROM anteriores
    GROUP BY id_atual
)

SELECT
    a.data_ref, a.id_contrato, a.id_cliente, a.status_contrato,

    COALESCE(m.qtd_contratos_anteriores, 0) AS qtd_contratos_anteriores,
    COALESCE(e.qtd_contratos_abertos, 0)    AS qtd_contratos_abertos,
    COALESCE(e.parcela_mensal_aberta, 0)    AS parcela_mensal_aberta,
    COALESCE(e.saldo_aberto_estimado, 0)    AS saldo_aberto_estimado,
    COALESCE(e.carteira_incompleta, 0)      AS carteira_incompleta,

    a.valor_parcela_atual / (c.renda_anual / 12.0)                                        AS parcela_sobre_renda_mensal,
    a.valor_credito_atual / c.renda_anual                                                 AS credito_sobre_renda_anual,
    (a.valor_parcela_atual + COALESCE(e.parcela_mensal_aberta, 0)) / (c.renda_anual / 12.0) AS comprometimento_renda,
    (a.valor_credito_atual + COALESCE(e.saldo_aberto_estimado, 0)) / c.renda_anual        AS exposicao_total_sobre_renda,
    a.valor_credito_atual / m.media_credito_historico                                     AS credito_atual_sobre_media_historica,
    a.valor_parcela_atual / m.media_parcela_historica                                     AS parcela_atual_sobre_parcela_media_hist
FROM atual a
LEFT JOIN base_cadastral c ON c.id_cliente = a.id_cliente
LEFT JOIN medias    m ON m.id_atual = a.id_contrato
LEFT JOIN exposicao e ON e.id_atual = a.id_contrato;