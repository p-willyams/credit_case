WITH tb_emprestimos AS (
    SELECT *,
    substr(data_decisao, 1, 10)  AS data_ref
    FROM base_historico_emprestimos
    WHERE status_contrato = 'Aprovado' OR status_contrato = 'Recusado'	 
),

atual AS (                                  
    SELECT
        a.id_contrato, a.id_cliente, a.data_ref,
        h.tipo_contrato,
        NULLIF(h.valor_solicitado, 0) AS valor_credito,   
        h.valor_bem,
        NULLIF(h.valor_parcela, 0)    AS valor_parcela,
        h.dia_semana_solicitacao,
        h.hora_solicitacao
    FROM tb_emprestimos a
    JOIN base_historico_emprestimos h ON h.id_contrato = a.id_contrato
),

anteriores AS (                                  
    SELECT
        a.id_contrato  AS id_atual,
        a.tipo_contrato AS tipo_atual,
        h.tipo_contrato AS tipo_ant,
        NULLIF(h.valor_solicitado, 0) AS credito_ant,     
        NULLIF(h.valor_parcela, 0)    AS parcela_ant,
        ROW_NUMBER() OVER (PARTITION BY a.id_contrato
                           ORDER BY substr(h.data_decisao, 1, 10) DESC, h.id_contrato DESC) AS ordem
    FROM atual a
    JOIN base_historico_emprestimos h
      ON h.id_cliente = a.id_cliente
     AND h.status_contrato = 'Aprovado'
     AND h.id_contrato <> a.id_contrato
     AND substr(h.data_decisao, 1, 10) < a.data_ref
),

resumo AS (
    SELECT
        id_atual,
        COUNT(*)                                       AS qtd_anteriores,
        MAX(credito_ant)                               AS max_credito_historico,
        MAX(tipo_ant = tipo_atual)                     AS tipo_ja_existia,
        MAX(CASE WHEN ordem = 1 THEN credito_ant END)  AS credito_ultimo,
        MAX(CASE WHEN ordem = 1 THEN parcela_ant END)  AS parcela_ultima
    FROM anteriores
    GROUP BY id_atual
)

SELECT
    a.data_ref, a.id_contrato, a.id_cliente,
    a.tipo_contrato, a.valor_credito, a.valor_bem, a.valor_parcela,

    a.dia_semana_solicitacao AS dia_semana,
    CASE WHEN a.dia_semana_solicitacao IS NULL THEN NULL
         WHEN a.dia_semana_solicitacao IN ('Sábado', 'Domingo') THEN 1 ELSE 0 END AS flag_fim_de_semana,
    CAST(substr(a.hora_solicitacao, 1, 2) AS INTEGER) AS hora,                -- assume 'HH...': validar o formato
    CASE WHEN CAST(substr(a.hora_solicitacao, 1, 2) AS INTEGER) < 6  THEN 'madrugada'
         WHEN CAST(substr(a.hora_solicitacao, 1, 2) AS INTEGER) < 12 THEN 'manha'
         WHEN CAST(substr(a.hora_solicitacao, 1, 2) AS INTEGER) < 18 THEN 'tarde'
         ELSE 'noite' END AS faixa_horaria,

    CASE WHEN a.valor_bem IS NULL OR a.valor_bem = 0 THEN 1 ELSE 0 END AS flag_sem_bem,
    1.0 * a.valor_bem / c.renda_anual                               AS valor_bem_sobre_renda_anual,
    1.0 * (a.valor_bem - a.valor_credito) / a.valor_bem             AS entrada_implicita_pct,
    1.0 * a.valor_credito / a.valor_bem                             AS credito_sobre_valor_bem,
    1.0 * a.valor_parcela / a.valor_credito                         AS parcela_sobre_credito,
    1.0 * a.valor_credito / a.valor_parcela                         AS prazo_implicito,


    a.valor_credito - r.credito_ultimo                              AS desvio_credito_vs_ultimo,
    1.0 * (a.valor_credito - r.credito_ultimo) / r.credito_ultimo   AS variacao_credito_vs_ultimo_pct,
    1.0 * (a.valor_parcela - r.parcela_ultima) / r.parcela_ultima   AS variacao_parcela_vs_ultima_pct,
    CASE WHEN a.valor_credito IS NULL OR r.max_credito_historico IS NULL THEN NULL
         WHEN a.valor_credito > r.max_credito_historico THEN 1 ELSE 0 END AS flag_credito_acima_max_historico,
    CASE WHEN r.qtd_anteriores IS NULL THEN NULL
         WHEN r.tipo_ja_existia = 1 THEN 0 ELSE 1 END                     AS flag_novo_tipo_contrato
FROM atual a
LEFT JOIN base_cadastral c ON c.id_cliente = a.id_cliente
LEFT JOIN resumo r         ON r.id_atual   = a.id_contrato;