WITH tb_emprestimos AS (
    SELECT
        id_contrato, id_cliente,
        substr(data_decisao, 1, 10) AS data_ref
    FROM base_historico_emprestimos
    WHERE status_contrato IN ('Aprovado', 'Recusado')
),

-- contratos com os campos de perfil já tratados
tb_contratos AS (
    SELECT
        *,
        -- área real: só quando a flag de "sem área" não está ativa
        CASE WHEN area_venda_sem_area = 1 OR area_venda IS NULL
             THEN NULL ELSE CAST(area_venda AS TEXT) END AS area_real,
        -- finalidade real: exclui nulo e os valores sem informação / não aplicável
        CASE WHEN finalidade_emprestimo IS NULL
               OR finalidade_emprestimo IN ('Não informado', 'Não se aplica', 'Cliente não informou a finalidade')
             THEN NULL ELSE finalidade_emprestimo END AS finalidade_real,
        -- finalidade não informada ('Não se aplica' não é falta de informação)
        CASE WHEN finalidade_emprestimo IS NULL
               OR finalidade_emprestimo IN ('Não informado', 'Cliente não informou a finalidade')
             THEN 1 ELSE 0 END AS flag_finalidade_nao_informada,
        CASE WHEN acompanhantes_cliente = 'Sozinho' THEN 1 ELSE 0 END AS flag_desacompanhado,
        CASE WHEN valor_entrada IS NOT NULL THEN 1 ELSE 0 END         AS flag_entrada_registrada
    FROM base_historico_emprestimos
),

historico AS (
    SELECT
        e.id_contrato AS id_atual,
        COUNT(*) AS qtd_total,
        SUM(CASE WHEN h.status_contrato = 'Aprovado' THEN 1 ELSE 0 END) AS qtd_aprovados,
        SUM(CASE WHEN h.status_contrato = 'Recusado' THEN 1 ELSE 0 END) AS qtd_recusados,
        SUM(CASE WHEN h.status_contrato = 'Cancelado' THEN 1 ELSE 0 END) AS qtd_cancelados,

        -- janelas antes da data_ref (qualquer status, por data_decisao)
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-7 days') THEN 1 ELSE 0 END) AS qtd_total_7d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-7 days') AND h.status_contrato = 'Aprovado' THEN 1 ELSE 0 END) AS qtd_aprovados_7d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-7 days') AND h.status_contrato = 'Recusado' THEN 1 ELSE 0 END) AS qtd_recusados_7d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-7 days') AND h.status_contrato = 'Cancelado' THEN 1 ELSE 0 END) AS qtd_cancelados_7d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-30 days') THEN 1 ELSE 0 END) AS qtd_total_30d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-30 days') AND h.status_contrato = 'Aprovado' THEN 1 ELSE 0 END) AS qtd_aprovados_30d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-30 days') AND h.status_contrato = 'Recusado' THEN 1 ELSE 0 END) AS qtd_recusados_30d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-30 days') AND h.status_contrato = 'Cancelado' THEN 1 ELSE 0 END) AS qtd_cancelados_30d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-90 days') THEN 1 ELSE 0 END) AS qtd_total_90d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-90 days') AND h.status_contrato = 'Aprovado' THEN 1 ELSE 0 END) AS qtd_aprovados_90d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-90 days') AND h.status_contrato = 'Recusado' THEN 1 ELSE 0 END) AS qtd_recusados_90d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-90 days') AND h.status_contrato = 'Cancelado' THEN 1 ELSE 0 END) AS qtd_cancelados_90d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-120 days') THEN 1 ELSE 0 END) AS qtd_total_120d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-120 days') AND h.status_contrato = 'Aprovado' THEN 1 ELSE 0 END) AS qtd_aprovados_120d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-120 days') AND h.status_contrato = 'Recusado' THEN 1 ELSE 0 END) AS qtd_recusados_120d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-120 days') AND h.status_contrato = 'Cancelado' THEN 1 ELSE 0 END) AS qtd_cancelados_120d,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-6 months') THEN 1 ELSE 0 END) AS qtd_total_6m,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-6 months') AND h.status_contrato = 'Aprovado' THEN 1 ELSE 0 END) AS qtd_aprovados_6m,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-6 months') AND h.status_contrato = 'Recusado' THEN 1 ELSE 0 END) AS qtd_recusados_6m,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-6 months') AND h.status_contrato = 'Cancelado' THEN 1 ELSE 0 END) AS qtd_cancelados_6m,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-12 months') THEN 1 ELSE 0 END) AS qtd_total_12m,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-12 months') AND h.status_contrato = 'Aprovado' THEN 1 ELSE 0 END) AS qtd_aprovados_12m,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-12 months') AND h.status_contrato = 'Recusado' THEN 1 ELSE 0 END) AS qtd_recusados_12m,
        SUM(CASE WHEN substr(h.data_decisao, 1, 10) >= date(e.data_ref, '-12 months') AND h.status_contrato = 'Cancelado' THEN 1 ELSE 0 END) AS qtd_cancelados_12m,

        -- recência e relacionamento (dias entre a data_ref e a data_decisao; NULL se o evento não existe)
        CAST(julianday(e.data_ref) - julianday(MAX(substr(h.data_decisao, 1, 10))) AS INTEGER) AS dias_desde_ultimo_contrato,
        CAST(julianday(e.data_ref) - julianday(MAX(CASE WHEN h.status_contrato = 'Aprovado' THEN substr(h.data_decisao, 1, 10) END)) AS INTEGER) AS dias_desde_ultimo_aprovado,
        CAST(julianday(e.data_ref) - julianday(MAX(CASE WHEN h.status_contrato = 'Recusado' THEN substr(h.data_decisao, 1, 10) END)) AS INTEGER) AS dias_desde_ultima_recusa,
        CAST(julianday(e.data_ref) - julianday(MIN(substr(h.data_decisao, 1, 10))) AS INTEGER) AS tempo_relacionamento_dias,
        -- média dos intervalos entre decisões consecutivas = (última - primeira) / (n - 1); NULL com menos de 2 contratos
        (julianday(MAX(substr(h.data_decisao, 1, 10))) - julianday(MIN(substr(h.data_decisao, 1, 10)))) / NULLIF(COUNT(*) - 1, 0) AS intervalo_medio_entre_contratos,

        -- recusas por motivo (só contratos com status Recusado)
        SUM(CASE WHEN h.status_contrato = 'Recusado' AND h.motivo_recusa = 'Desistência do cliente' THEN 1 ELSE 0 END) AS qtd_recusa_desistencia_cliente,
        SUM(CASE WHEN h.status_contrato = 'Recusado' AND h.motivo_recusa = 'Erro de sistema' THEN 1 ELSE 0 END) AS qtd_recusa_erro_sistema,
        SUM(CASE WHEN h.status_contrato = 'Recusado' AND h.motivo_recusa = 'Histórico de crédito' THEN 1 ELSE 0 END) AS qtd_recusa_historico_credito,
        SUM(CASE WHEN h.status_contrato = 'Recusado' AND h.motivo_recusa = 'Limite excedido' THEN 1 ELSE 0 END) AS qtd_recusa_limite_excedido,
        SUM(CASE WHEN h.status_contrato = 'Recusado' AND h.motivo_recusa = 'Não informado' THEN 1 ELSE 0 END) AS qtd_recusa_nao_informado,
        SUM(CASE WHEN h.status_contrato = 'Recusado' AND h.motivo_recusa = 'Não se aplica' THEN 1 ELSE 0 END) AS qtd_recusa_nao_se_aplica,
        SUM(CASE WHEN h.status_contrato = 'Recusado' AND h.motivo_recusa = 'Pontuação antifraude' THEN 1 ELSE 0 END) AS qtd_recusa_pontuacao_antifraude,
        SUM(CASE WHEN h.status_contrato = 'Recusado' AND h.motivo_recusa = 'Pontuação baixa' THEN 1 ELSE 0 END) AS qtd_recusa_pontuacao_baixa,
        SUM(CASE WHEN h.status_contrato = 'Recusado' AND h.motivo_recusa = 'Verificação cadastral' THEN 1 ELSE 0 END) AS qtd_recusa_verificacao_cadastral,

        -- contratos por tipo de contrato
        SUM(CASE WHEN h.tipo_contrato = 'Crédito Rotativo' THEN 1 ELSE 0 END) AS qtd_tipo_credito_rotativo,
        SUM(CASE WHEN h.tipo_contrato = 'Empréstimo em Dinheiro' THEN 1 ELSE 0 END) AS qtd_tipo_emprestimo_dinheiro,
        SUM(CASE WHEN h.tipo_contrato = 'Financiamento de Consumo' THEN 1 ELSE 0 END) AS qtd_tipo_financiamento_consumo,

        -- contratos por tipo de produto
        SUM(CASE WHEN h.tipo_produto = 'atendimento espontâneo' THEN 1 ELSE 0 END) AS qtd_produto_atendimento_espontaneo,
        SUM(CASE WHEN h.tipo_produto = 'venda cruzada' THEN 1 ELSE 0 END) AS qtd_produto_venda_cruzada,
        SUM(CASE WHEN h.tipo_produto = 'Não informado' THEN 1 ELSE 0 END) AS qtd_produto_nao_informado,

        -- tipos de produto distintos ('Não informado' não conta como tipo)
        COUNT(DISTINCT CASE WHEN h.tipo_produto <> 'Não informado' THEN h.tipo_produto END) AS qtd_tipos_produto_distintos,

        -- área de venda
        SUM(h.area_venda_sem_area) AS qtd_sem_area,
        COUNT(DISTINCT h.area_real) AS qtd_areas_distintas,

        -- finalidade do empréstimo
        COUNT(DISTINCT h.finalidade_real) AS qtd_finalidades_distintas,
        SUM(h.flag_finalidade_nao_informada) AS qtd_finalidade_nao_informada,
        SUM(CASE WHEN h.status_contrato = 'Aprovado' THEN h.flag_finalidade_nao_informada ELSE 0 END) AS qtd_finalidade_nao_informada_aprovados,
        SUM(CASE WHEN h.status_contrato = 'Recusado' THEN h.flag_finalidade_nao_informada ELSE 0 END) AS qtd_finalidade_nao_informada_recusados,

        -- cliente desacompanhado
        SUM(h.flag_desacompanhado) AS qtd_desacompanhado,
        SUM(CASE WHEN h.status_contrato = 'Aprovado' THEN h.flag_desacompanhado ELSE 0 END) AS qtd_desacompanhado_aprovados,
        SUM(CASE WHEN h.status_contrato = 'Recusado' THEN h.flag_desacompanhado ELSE 0 END) AS qtd_desacompanhado_recusados,

        -- entrada registrada
        SUM(h.flag_entrada_registrada) AS qtd_entrada_registrada
    FROM tb_emprestimos e
    JOIN tb_contratos h
      ON h.id_cliente = e.id_cliente
     AND h.id_contrato <> e.id_contrato
     AND substr(h.data_decisao, 1, 10) < e.data_ref
    GROUP BY e.id_contrato
),

tb_features AS (
    SELECT
        e.id_contrato, e.id_cliente, e.data_ref,

        CASE WHEN h.qtd_total IS NULL THEN 1 ELSE 0 END AS flag_cliente_sem_historico,

        COALESCE(h.qtd_total, 0) AS qtd_total,
        COALESCE(h.qtd_aprovados, 0) AS qtd_aprovados,
        1.0 * h.qtd_aprovados / h.qtd_total AS pct_aprovados,
        COALESCE(h.qtd_recusados, 0) AS qtd_recusados,
        1.0 * h.qtd_recusados / h.qtd_total AS pct_recusados,
        COALESCE(h.qtd_cancelados, 0) AS qtd_cancelados,
        1.0 * h.qtd_cancelados / h.qtd_total AS pct_cancelados,

        -- janela 7d (pct sobre o total da janela; NULL se não houve contrato)
        COALESCE(h.qtd_total_7d, 0) AS qtd_total_7d,
        COALESCE(h.qtd_aprovados_7d, 0) AS qtd_aprovados_7d,
        1.0 * h.qtd_aprovados_7d / h.qtd_total_7d AS pct_aprovados_7d,
        COALESCE(h.qtd_recusados_7d, 0) AS qtd_recusados_7d,
        1.0 * h.qtd_recusados_7d / h.qtd_total_7d AS pct_recusados_7d,
        COALESCE(h.qtd_cancelados_7d, 0) AS qtd_cancelados_7d,
        1.0 * h.qtd_cancelados_7d / h.qtd_total_7d AS pct_cancelados_7d,

        -- janela 30d (pct sobre o total da janela; NULL se não houve contrato)
        COALESCE(h.qtd_total_30d, 0) AS qtd_total_30d,
        COALESCE(h.qtd_aprovados_30d, 0) AS qtd_aprovados_30d,
        1.0 * h.qtd_aprovados_30d / h.qtd_total_30d AS pct_aprovados_30d,
        COALESCE(h.qtd_recusados_30d, 0) AS qtd_recusados_30d,
        1.0 * h.qtd_recusados_30d / h.qtd_total_30d AS pct_recusados_30d,
        COALESCE(h.qtd_cancelados_30d, 0) AS qtd_cancelados_30d,
        1.0 * h.qtd_cancelados_30d / h.qtd_total_30d AS pct_cancelados_30d,

        -- janela 90d (pct sobre o total da janela; NULL se não houve contrato)
        COALESCE(h.qtd_total_90d, 0) AS qtd_total_90d,
        COALESCE(h.qtd_aprovados_90d, 0) AS qtd_aprovados_90d,
        1.0 * h.qtd_aprovados_90d / h.qtd_total_90d AS pct_aprovados_90d,
        COALESCE(h.qtd_recusados_90d, 0) AS qtd_recusados_90d,
        1.0 * h.qtd_recusados_90d / h.qtd_total_90d AS pct_recusados_90d,
        COALESCE(h.qtd_cancelados_90d, 0) AS qtd_cancelados_90d,
        1.0 * h.qtd_cancelados_90d / h.qtd_total_90d AS pct_cancelados_90d,

        -- janela 120d (pct sobre o total da janela; NULL se não houve contrato)
        COALESCE(h.qtd_total_120d, 0) AS qtd_total_120d,
        COALESCE(h.qtd_aprovados_120d, 0) AS qtd_aprovados_120d,
        1.0 * h.qtd_aprovados_120d / h.qtd_total_120d AS pct_aprovados_120d,
        COALESCE(h.qtd_recusados_120d, 0) AS qtd_recusados_120d,
        1.0 * h.qtd_recusados_120d / h.qtd_total_120d AS pct_recusados_120d,
        COALESCE(h.qtd_cancelados_120d, 0) AS qtd_cancelados_120d,
        1.0 * h.qtd_cancelados_120d / h.qtd_total_120d AS pct_cancelados_120d,

        -- janela 6m (pct sobre o total da janela; NULL se não houve contrato)
        COALESCE(h.qtd_total_6m, 0) AS qtd_total_6m,
        COALESCE(h.qtd_aprovados_6m, 0) AS qtd_aprovados_6m,
        1.0 * h.qtd_aprovados_6m / h.qtd_total_6m AS pct_aprovados_6m,
        COALESCE(h.qtd_recusados_6m, 0) AS qtd_recusados_6m,
        1.0 * h.qtd_recusados_6m / h.qtd_total_6m AS pct_recusados_6m,
        COALESCE(h.qtd_cancelados_6m, 0) AS qtd_cancelados_6m,
        1.0 * h.qtd_cancelados_6m / h.qtd_total_6m AS pct_cancelados_6m,

        -- janela 12m (pct sobre o total da janela; NULL se não houve contrato)
        COALESCE(h.qtd_total_12m, 0) AS qtd_total_12m,
        COALESCE(h.qtd_aprovados_12m, 0) AS qtd_aprovados_12m,
        1.0 * h.qtd_aprovados_12m / h.qtd_total_12m AS pct_aprovados_12m,
        COALESCE(h.qtd_recusados_12m, 0) AS qtd_recusados_12m,
        1.0 * h.qtd_recusados_12m / h.qtd_total_12m AS pct_recusados_12m,
        COALESCE(h.qtd_cancelados_12m, 0) AS qtd_cancelados_12m,
        1.0 * h.qtd_cancelados_12m / h.qtd_total_12m AS pct_cancelados_12m,

        -- razão entre janelas (NULL se a janela maior não tem contratos)
        1.0 * h.qtd_total_30d / h.qtd_total_90d AS qtd_total_30d_vs_90d,
        1.0 * h.qtd_total_90d / h.qtd_total_120d AS qtd_total_90d_vs_120d,

        -- recência e relacionamento (NULL se o cliente não tem o evento)
        h.dias_desde_ultimo_contrato AS dias_desde_ultimo_contrato,
        h.dias_desde_ultimo_aprovado AS dias_desde_ultimo_aprovado,
        h.dias_desde_ultima_recusa AS dias_desde_ultima_recusa,
        h.tempo_relacionamento_dias AS tempo_relacionamento_dias,
        h.intervalo_medio_entre_contratos AS intervalo_medio_entre_contratos,

        -- motivos de recusa: pct sobre o total de recusas (NULL se nunca recusado)
        COALESCE(h.qtd_recusa_desistencia_cliente, 0) AS qtd_recusa_desistencia_cliente,
        1.0 * h.qtd_recusa_desistencia_cliente / h.qtd_recusados AS pct_recusa_desistencia_cliente,
        COALESCE(h.qtd_recusa_erro_sistema, 0) AS qtd_recusa_erro_sistema,
        1.0 * h.qtd_recusa_erro_sistema / h.qtd_recusados AS pct_recusa_erro_sistema,
        COALESCE(h.qtd_recusa_historico_credito, 0) AS qtd_recusa_historico_credito,
        1.0 * h.qtd_recusa_historico_credito / h.qtd_recusados AS pct_recusa_historico_credito,
        COALESCE(h.qtd_recusa_limite_excedido, 0) AS qtd_recusa_limite_excedido,
        1.0 * h.qtd_recusa_limite_excedido / h.qtd_recusados AS pct_recusa_limite_excedido,
        COALESCE(h.qtd_recusa_nao_informado, 0) AS qtd_recusa_nao_informado,
        1.0 * h.qtd_recusa_nao_informado / h.qtd_recusados AS pct_recusa_nao_informado,
        COALESCE(h.qtd_recusa_nao_se_aplica, 0) AS qtd_recusa_nao_se_aplica,
        1.0 * h.qtd_recusa_nao_se_aplica / h.qtd_recusados AS pct_recusa_nao_se_aplica,
        COALESCE(h.qtd_recusa_pontuacao_antifraude, 0) AS qtd_recusa_pontuacao_antifraude,
        1.0 * h.qtd_recusa_pontuacao_antifraude / h.qtd_recusados AS pct_recusa_pontuacao_antifraude,
        COALESCE(h.qtd_recusa_pontuacao_baixa, 0) AS qtd_recusa_pontuacao_baixa,
        1.0 * h.qtd_recusa_pontuacao_baixa / h.qtd_recusados AS pct_recusa_pontuacao_baixa,
        COALESCE(h.qtd_recusa_verificacao_cadastral, 0) AS qtd_recusa_verificacao_cadastral,
        1.0 * h.qtd_recusa_verificacao_cadastral / h.qtd_recusados AS pct_recusa_verificacao_cadastral,

        -- tipo de contrato: pct sobre o total de contratos anteriores
        COALESCE(h.qtd_tipo_credito_rotativo, 0) AS qtd_tipo_credito_rotativo,
        1.0 * h.qtd_tipo_credito_rotativo / h.qtd_total AS pct_tipo_credito_rotativo,
        COALESCE(h.qtd_tipo_emprestimo_dinheiro, 0) AS qtd_tipo_emprestimo_dinheiro,
        1.0 * h.qtd_tipo_emprestimo_dinheiro / h.qtd_total AS pct_tipo_emprestimo_dinheiro,
        COALESCE(h.qtd_tipo_financiamento_consumo, 0) AS qtd_tipo_financiamento_consumo,
        1.0 * h.qtd_tipo_financiamento_consumo / h.qtd_total AS pct_tipo_financiamento_consumo,

        -- tipo de produto: pct sobre o total de contratos anteriores
        COALESCE(h.qtd_produto_atendimento_espontaneo, 0) AS qtd_produto_atendimento_espontaneo,
        1.0 * h.qtd_produto_atendimento_espontaneo / h.qtd_total AS pct_produto_atendimento_espontaneo,
        COALESCE(h.qtd_produto_venda_cruzada, 0) AS qtd_produto_venda_cruzada,
        1.0 * h.qtd_produto_venda_cruzada / h.qtd_total AS pct_produto_venda_cruzada,
        COALESCE(h.qtd_produto_nao_informado, 0) AS qtd_produto_nao_informado,
        1.0 * h.qtd_produto_nao_informado / h.qtd_total AS pct_produto_nao_informado,

        COALESCE(h.qtd_tipos_produto_distintos, 0) AS qtd_tipos_produto_distintos,

        -- área de venda: pct sobre o total de contratos anteriores
        1.0 * h.qtd_sem_area / h.qtd_total AS pct_contratos_sem_area,
        COALESCE(h.qtd_areas_distintas, 0) AS qtd_areas_distintas,

        -- finalidade: pct sobre o total, sobre os aprovados e sobre os recusados
        COALESCE(h.qtd_finalidades_distintas, 0) AS qtd_finalidades_distintas,
        1.0 * h.qtd_finalidade_nao_informada / h.qtd_total AS pct_finalidade_nao_informada,
        1.0 * h.qtd_finalidade_nao_informada_aprovados / h.qtd_aprovados AS pct_finalidade_nao_informada_aprovados,
        1.0 * h.qtd_finalidade_nao_informada_recusados / h.qtd_recusados AS pct_finalidade_nao_informada_recusados,

        -- desacompanhado: pct sobre o total, sobre os aprovados e sobre os recusados
        1.0 * h.qtd_desacompanhado / h.qtd_total AS pct_desacompanhado,
        1.0 * h.qtd_desacompanhado_aprovados / h.qtd_aprovados AS pct_desacompanhado_aprovados,
        1.0 * h.qtd_desacompanhado_recusados / h.qtd_recusados AS pct_desacompanhado_recusados,

        -- entrada registrada (valor_entrada não nulo): pct sobre o total
        1.0 * h.qtd_entrada_registrada / h.qtd_total AS pct_entrada_registrada
    FROM tb_emprestimos e
    LEFT JOIN historico h ON h.id_atual = e.id_contrato
)

SELECT
        data_ref,
        id_contrato,
        id_cliente,
        flag_cliente_sem_historico,
        qtd_total,
        qtd_aprovados,
        pct_aprovados,
        qtd_recusados,
        pct_recusados,
        qtd_cancelados,
        pct_cancelados,
        qtd_total_7d,
        qtd_aprovados_7d,
        pct_aprovados_7d,
        qtd_recusados_7d,
        pct_recusados_7d,
        qtd_cancelados_7d,
        pct_cancelados_7d,
        qtd_total_30d,
        qtd_aprovados_30d,
        pct_aprovados_30d,
        qtd_recusados_30d,
        pct_recusados_30d,
        qtd_cancelados_30d,
        pct_cancelados_30d,
        qtd_total_90d,
        qtd_aprovados_90d,
        pct_aprovados_90d,
        qtd_recusados_90d,
        pct_recusados_90d,
        qtd_cancelados_90d,
        pct_cancelados_90d,
        qtd_total_120d,
        qtd_aprovados_120d,
        pct_aprovados_120d,
        qtd_recusados_120d,
        pct_recusados_120d,
        qtd_cancelados_120d,
        pct_cancelados_120d,
        qtd_total_6m,
        qtd_aprovados_6m,
        pct_aprovados_6m,
        qtd_recusados_6m,
        pct_recusados_6m,
        qtd_cancelados_6m,
        pct_cancelados_6m,
        qtd_total_12m,
        qtd_aprovados_12m,
        pct_aprovados_12m,
        qtd_recusados_12m,
        pct_recusados_12m,
        qtd_cancelados_12m,
        pct_cancelados_12m,
        qtd_total_30d_vs_90d,
        qtd_total_90d_vs_120d,
        dias_desde_ultimo_contrato,
        dias_desde_ultimo_aprovado,
        dias_desde_ultima_recusa,
        tempo_relacionamento_dias,
        intervalo_medio_entre_contratos,
        qtd_recusa_desistencia_cliente,
        pct_recusa_desistencia_cliente,
        qtd_recusa_erro_sistema,
        pct_recusa_erro_sistema,
        qtd_recusa_historico_credito,
        pct_recusa_historico_credito,
        qtd_recusa_limite_excedido,
        pct_recusa_limite_excedido,
        qtd_recusa_nao_informado,
        pct_recusa_nao_informado,
        qtd_recusa_nao_se_aplica,
        pct_recusa_nao_se_aplica,
        qtd_recusa_pontuacao_antifraude,
        pct_recusa_pontuacao_antifraude,
        qtd_recusa_pontuacao_baixa,
        pct_recusa_pontuacao_baixa,
        qtd_recusa_verificacao_cadastral,
        pct_recusa_verificacao_cadastral,
        qtd_tipo_credito_rotativo,
        pct_tipo_credito_rotativo,
        qtd_tipo_emprestimo_dinheiro,
        pct_tipo_emprestimo_dinheiro,
        qtd_tipo_financiamento_consumo,
        pct_tipo_financiamento_consumo,
        qtd_produto_atendimento_espontaneo,
        pct_produto_atendimento_espontaneo,
        qtd_produto_venda_cruzada,
        pct_produto_venda_cruzada,
        qtd_produto_nao_informado,
        pct_produto_nao_informado,
        qtd_tipos_produto_distintos,
        pct_contratos_sem_area,
        qtd_areas_distintas,
        qtd_finalidades_distintas,
        pct_finalidade_nao_informada,
        pct_finalidade_nao_informada_aprovados,
        pct_finalidade_nao_informada_recusados,
        pct_desacompanhado,
        pct_desacompanhado_aprovados,
        pct_desacompanhado_recusados,
        pct_entrada_registrada
FROM tb_features

