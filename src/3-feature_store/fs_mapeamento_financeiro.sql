WITH tb_emprestimos AS (
    SELECT
        id_contrato, id_cliente,
        substr(data_decisao, 1, 10) AS data_ref,
        NULLIF(valor_solicitado, 0) AS valor_credito_atual,
        NULLIF(valor_parcela, 0)    AS valor_parcela_atual,
        tipo_produto                AS tipo_produto_atual,
        tipo_contrato               AS tipo_contrato_atual
    FROM base_historico_emprestimos
    WHERE status_contrato IN ('Aprovado', 'Recusado')
),

-- contratos anteriores aprovados do cliente, decididos antes da data_ref
anteriores AS (
    SELECT
        e.id_contrato AS id_atual,
        e.data_ref,
        substr(h.data_decisao, 1, 10) AS data_decisao_ant,
        NULLIF(h.valor_solicitado, 0) AS credito_ant,
        NULLIF(h.valor_credito, 0) AS credito_concedido,
        NULLIF(h.valor_parcela, 0) AS parcela_ant,
        h.tipo_produto AS tipo_produto_ant,
        h.tipo_contrato AS tipo_contrato_ant,
        e.tipo_produto_atual,
        e.tipo_contrato_atual,
        NULLIF(h.qtd_parcelas_planejadas, 0) AS parcelas_planejadas,
        h.percentual_entrada AS pct_entrada,
        CASE WHEN h.flag_seguro_contratado IS NULL THEN NULL
             WHEN h.flag_seguro_contratado = 1 THEN 1.0 ELSE 0.0 END AS com_seguro,
        -- contrato aberto na data_ref: liberado e ainda não encerrado
        CASE WHEN h.data_liberacao IS NOT NULL
              AND substr(h.data_liberacao, 1, 10) <= e.data_ref
              AND (h.data_encerramento IS NULL OR substr(h.data_encerramento, 1, 10) > e.data_ref)
             THEN 1 ELSE 0 END AS contrato_aberto,
        ROW_NUMBER() OVER (PARTITION BY e.id_contrato
                           ORDER BY substr(h.data_decisao, 1, 10) DESC, h.id_contrato DESC) AS ordem
    FROM tb_emprestimos e
    JOIN base_historico_emprestimos h
      ON h.id_cliente = e.id_cliente
     AND h.status_contrato = 'Aprovado'
     AND h.id_contrato <> e.id_contrato
     AND substr(h.data_decisao, 1, 10) < e.data_ref
),

-- tipo de produto mais comum no histórico ('Não informado' não conta; empate: o usado mais recentemente)
moda_produto AS (
    SELECT id_atual, tipo_produto_ant AS tipo_produto_mais_comum
    FROM (
        SELECT
            id_atual, tipo_produto_ant,
            ROW_NUMBER() OVER (PARTITION BY id_atual
                               ORDER BY COUNT(*) DESC, MAX(data_decisao_ant) DESC, tipo_produto_ant) AS rn
        FROM anteriores
        WHERE tipo_produto_ant IS NOT NULL AND tipo_produto_ant <> 'Não informado'
        GROUP BY id_atual, tipo_produto_ant
    )
    WHERE rn = 1
),

-- tipo de contrato mais comum no histórico (empate: o usado mais recentemente)
moda_contrato AS (
    SELECT id_atual, tipo_contrato_ant AS tipo_contrato_mais_comum
    FROM (
        SELECT
            id_atual, tipo_contrato_ant,
            ROW_NUMBER() OVER (PARTITION BY id_atual
                               ORDER BY COUNT(*) DESC, MAX(data_decisao_ant) DESC, tipo_contrato_ant) AS rn
        FROM anteriores
        WHERE tipo_contrato_ant IS NOT NULL
        GROUP BY id_atual, tipo_contrato_ant
    )
    WHERE rn = 1
),

historico AS (
    SELECT
        id_atual,
        SUM(credito_ant)                                   AS valor_credito_soma,
        AVG(credito_ant)                                   AS valor_credito_media,
        MAX(credito_ant)                                   AS valor_credito_max,
        MAX(CASE WHEN ordem = 1 THEN credito_ant END)      AS valor_credito_ultimo,

        -- condições dos contratos anteriores
        -- razão concedido/solicitado: média do concedido / média do solicitado, só em contratos com os dois valores
        AVG(CASE WHEN credito_concedido IS NOT NULL AND credito_ant IS NOT NULL THEN credito_concedido END)
          / AVG(CASE WHEN credito_concedido IS NOT NULL AND credito_ant IS NOT NULL THEN credito_ant END) AS razao_credito_solicitado,
        AVG(parcelas_planejadas)                           AS prazo_medio_planejado,
        AVG(pct_entrada)                                   AS percentual_entrada_medio,
        AVG(com_seguro)                                    AS pct_com_seguro,
        SUM(contrato_aberto)                               AS qtd_contratos_abertos,

        -- exposição dos contratos ainda abertos
        SUM(CASE WHEN contrato_aberto = 1 THEN credito_ant END) AS valor_credito_aberto,
        SUM(CASE WHEN contrato_aberto = 1 THEN parcela_ant END) AS soma_parcelas_abertas,

        -- média das parcelas dos últimos 6 meses (base para a variação da parcela)
        AVG(CASE WHEN data_decisao_ant >= date(data_ref, '-6 months') THEN parcela_ant END) AS parcela_media_6m,

        -- tipos: do contrato anterior mais recente e quantos contratos anteriores tiveram o mesmo tipo do atual
        MAX(CASE WHEN ordem = 1 THEN tipo_produto_ant END)  AS tipo_produto_ultimo,
        MAX(CASE WHEN ordem = 1 THEN tipo_contrato_ant END) AS tipo_contrato_ultimo,
        SUM(CASE WHEN tipo_produto_ant = tipo_produto_atual THEN 1 ELSE 0 END)   AS qtd_mesmo_tipo_produto,
        SUM(CASE WHEN tipo_contrato_ant = tipo_contrato_atual THEN 1 ELSE 0 END) AS qtd_mesmo_tipo_contrato,

        -- janela 30d
        SUM(CASE WHEN data_decisao_ant >= date(data_ref, '-30 days') THEN credito_ant END) AS valor_credito_soma_30d,
        AVG(CASE WHEN data_decisao_ant >= date(data_ref, '-30 days') THEN credito_ant END) AS valor_credito_media_30d,
        MAX(CASE WHEN data_decisao_ant >= date(data_ref, '-30 days') THEN credito_ant END) AS valor_credito_max_30d,

        -- janela 90d
        SUM(CASE WHEN data_decisao_ant >= date(data_ref, '-90 days') THEN credito_ant END) AS valor_credito_soma_90d,
        AVG(CASE WHEN data_decisao_ant >= date(data_ref, '-90 days') THEN credito_ant END) AS valor_credito_media_90d,
        MAX(CASE WHEN data_decisao_ant >= date(data_ref, '-90 days') THEN credito_ant END) AS valor_credito_max_90d,

        -- janela 120d
        SUM(CASE WHEN data_decisao_ant >= date(data_ref, '-120 days') THEN credito_ant END) AS valor_credito_soma_120d,
        AVG(CASE WHEN data_decisao_ant >= date(data_ref, '-120 days') THEN credito_ant END) AS valor_credito_media_120d,
        MAX(CASE WHEN data_decisao_ant >= date(data_ref, '-120 days') THEN credito_ant END) AS valor_credito_max_120d,

        -- janela 6m
        SUM(CASE WHEN data_decisao_ant >= date(data_ref, '-6 months') THEN credito_ant END) AS valor_credito_soma_6m,
        AVG(CASE WHEN data_decisao_ant >= date(data_ref, '-6 months') THEN credito_ant END) AS valor_credito_media_6m,
        MAX(CASE WHEN data_decisao_ant >= date(data_ref, '-6 months') THEN credito_ant END) AS valor_credito_max_6m,

        -- janela 12m
        SUM(CASE WHEN data_decisao_ant >= date(data_ref, '-12 months') THEN credito_ant END) AS valor_credito_soma_12m,
        AVG(CASE WHEN data_decisao_ant >= date(data_ref, '-12 months') THEN credito_ant END) AS valor_credito_media_12m,
        MAX(CASE WHEN data_decisao_ant >= date(data_ref, '-12 months') THEN credito_ant END) AS valor_credito_max_12m
    FROM anteriores
    GROUP BY id_atual
),

tb_features AS (
    SELECT
        e.id_contrato, e.id_cliente, e.data_ref,

        COALESCE(h.valor_credito_soma, 0) AS valor_credito_soma,
        h.valor_credito_media AS valor_credito_media,
        h.valor_credito_max AS valor_credito_max,
        h.valor_credito_ultimo AS valor_credito_ultimo,

        -- janela 30d
        COALESCE(h.valor_credito_soma_30d, 0) AS valor_credito_soma_30d,
        h.valor_credito_media_30d AS valor_credito_media_30d,
        h.valor_credito_max_30d AS valor_credito_max_30d,

        -- janela 90d
        COALESCE(h.valor_credito_soma_90d, 0) AS valor_credito_soma_90d,
        h.valor_credito_media_90d AS valor_credito_media_90d,
        h.valor_credito_max_90d AS valor_credito_max_90d,

        -- janela 120d
        COALESCE(h.valor_credito_soma_120d, 0) AS valor_credito_soma_120d,
        h.valor_credito_media_120d AS valor_credito_media_120d,
        h.valor_credito_max_120d AS valor_credito_max_120d,

        -- janela 6m
        COALESCE(h.valor_credito_soma_6m, 0) AS valor_credito_soma_6m,
        h.valor_credito_media_6m AS valor_credito_media_6m,
        h.valor_credito_max_6m AS valor_credito_max_6m,

        -- janela 12m
        COALESCE(h.valor_credito_soma_12m, 0) AS valor_credito_soma_12m,
        h.valor_credito_media_12m AS valor_credito_media_12m,
        h.valor_credito_max_12m AS valor_credito_max_12m,

        -- condições dos contratos anteriores
        h.razao_credito_solicitado AS razao_credito_solicitado,
        h.prazo_medio_planejado AS prazo_medio_planejado,
        h.percentual_entrada_medio AS percentual_entrada_medio,
        h.pct_com_seguro AS pct_com_seguro,
        COALESCE(h.qtd_contratos_abertos, 0) AS qtd_contratos_abertos,

        -- exposição dos contratos ainda abertos
        COALESCE(h.valor_credito_aberto, 0) AS valor_credito_aberto,
        COALESCE(h.soma_parcelas_abertas, 0) AS soma_parcelas_abertas,

        -- contrato atual vs média das janelas (NULL se não há contrato anterior na janela ou valor atual)
        e.valor_credito_atual - h.valor_credito_media_6m AS variacao_credito_vs_media_6m,
        e.valor_parcela_atual - h.parcela_media_6m AS variacao_parcela_vs_media_6m,
        1.0 * e.valor_credito_atual / h.valor_credito_media_6m AS razao_credito_atual_media_6m,
        1.0 * e.valor_credito_atual / h.valor_credito_media_12m AS razao_credito_atual_media_12m,

        -- tipo de produto (NULL se não há histórico ou o tipo é 'Não informado')
        CASE WHEN h.tipo_produto_ultimo IS NULL OR h.tipo_produto_ultimo = 'Não informado'
               OR e.tipo_produto_atual IS NULL OR e.tipo_produto_atual = 'Não informado' THEN NULL
             WHEN e.tipo_produto_atual <> h.tipo_produto_ultimo THEN 1 ELSE 0 END AS mudanca_tipo_produto,
        CASE WHEN mp.tipo_produto_mais_comum IS NULL
               OR e.tipo_produto_atual IS NULL OR e.tipo_produto_atual = 'Não informado' THEN NULL
             WHEN e.tipo_produto_atual <> mp.tipo_produto_mais_comum THEN 1 ELSE 0 END AS mudanca_tipo_produto_mais_comum,
        CASE WHEN h.qtd_mesmo_tipo_produto IS NULL
               OR e.tipo_produto_atual IS NULL OR e.tipo_produto_atual = 'Não informado' THEN NULL
             WHEN h.qtd_mesmo_tipo_produto = 0 THEN 1 ELSE 0 END AS flag_primeira_vez_tipo_produto,

        -- tipo de contrato (NULL se não há histórico)
        CASE WHEN h.tipo_contrato_ultimo IS NULL OR e.tipo_contrato_atual IS NULL THEN NULL
             WHEN e.tipo_contrato_atual <> h.tipo_contrato_ultimo THEN 1 ELSE 0 END AS mudanca_tipo_contrato,
        CASE WHEN mc.tipo_contrato_mais_comum IS NULL OR e.tipo_contrato_atual IS NULL THEN NULL
             WHEN e.tipo_contrato_atual <> mc.tipo_contrato_mais_comum THEN 1 ELSE 0 END AS mudanca_tipo_contrato_mais_comum,
        CASE WHEN h.qtd_mesmo_tipo_contrato IS NULL OR e.tipo_contrato_atual IS NULL THEN NULL
             WHEN h.qtd_mesmo_tipo_contrato = 0 THEN 1 ELSE 0 END AS flag_primeira_vez_tipo_contrato
    FROM tb_emprestimos e
    LEFT JOIN historico h ON h.id_atual = e.id_contrato
    LEFT JOIN moda_produto mp ON mp.id_atual = e.id_contrato
    LEFT JOIN moda_contrato mc ON mc.id_atual = e.id_contrato
)

SELECT
    data_ref,
    id_contrato,
    id_cliente,
    valor_credito_soma,
    valor_credito_media,
    valor_credito_max,
    valor_credito_ultimo,
    valor_credito_soma_30d,
    valor_credito_media_30d,
    valor_credito_max_30d,
    valor_credito_soma_90d,
    valor_credito_media_90d,
    valor_credito_max_90d,
    valor_credito_soma_120d,
    valor_credito_media_120d,
    valor_credito_max_120d,
    valor_credito_soma_6m,
    valor_credito_media_6m,
    valor_credito_max_6m,
    valor_credito_soma_12m,
    valor_credito_media_12m,
    valor_credito_max_12m,
    razao_credito_solicitado,
    prazo_medio_planejado,
    percentual_entrada_medio,
    pct_com_seguro,
    qtd_contratos_abertos,
    valor_credito_aberto,
    soma_parcelas_abertas,
    variacao_credito_vs_media_6m,
    variacao_parcela_vs_media_6m,
    razao_credito_atual_media_6m,
    razao_credito_atual_media_12m,
    mudanca_tipo_produto,
    mudanca_tipo_produto_mais_comum,
    flag_primeira_vez_tipo_produto,
    mudanca_tipo_contrato,
    mudanca_tipo_contrato_mais_comum,
    flag_primeira_vez_tipo_contrato
FROM tb_features