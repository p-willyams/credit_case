WITH tb_emprestimos AS (
    SELECT *,
    substr(data_decisao, 1, 10)  AS data_ref
    FROM base_historico_emprestimos
    WHERE status_contrato = 'Aprovado' OR status_contrato = 'Recusado'	 
),

tb_cadastral AS (
    SELECT
        id_cliente,
        data_nascimento,
        estado_civil, tipo_renda, nivel_educacao, ocupacao, tipo_organizacao, tipo_moradia,
        CASE possui_carro  WHEN 'Sim' THEN 1 WHEN 'Não' THEN 0 END AS possui_carro,     -- 'Não informado' e NULL ficam NULL
        CASE possui_imovel WHEN 'Sim' THEN 1 WHEN 'Não' THEN 0 END AS possui_imovel,
        qtd_filhos, qtd_membros_familia, renda_anual,
        nota_regiao_cliente, nota_regiao_cliente_cidade,
        membros_invalido, data_nascimento_invalida
    FROM base_cadastral
),

juntado AS (
    SELECT
        a.id_contrato, a.id_cliente, a.data_ref,
        CASE WHEN c.id_cliente IS NULL THEN 1 ELSE 0 END AS cliente_sem_cadastro,
        c.data_nascimento,
        COALESCE(c.estado_civil,     'Sem cadastro') AS estado_civil,
        COALESCE(c.tipo_renda,       'Sem cadastro') AS tipo_renda,
        COALESCE(c.nivel_educacao,   'Sem cadastro') AS nivel_educacao,
        COALESCE(c.ocupacao,         'Sem cadastro') AS ocupacao,
        COALESCE(c.tipo_organizacao, 'Sem cadastro') AS tipo_organizacao,
        COALESCE(c.tipo_moradia,     'Sem cadastro') AS tipo_moradia,
        c.possui_carro, c.possui_imovel,
        c.qtd_filhos, c.qtd_membros_familia, c.renda_anual,
        c.nota_regiao_cliente, c.nota_regiao_cliente_cidade,
        c.renda_anual / 12.0 AS renda_mensal,
        CASE WHEN (julianday(a.data_ref) - julianday(c.data_nascimento)) / 365.25 BETWEEN 18 AND 100
             THEN (julianday(a.data_ref) - julianday(c.data_nascimento)) / 365.25 END AS idade
    FROM tb_emprestimos a
    LEFT JOIN tb_cadastral c ON c.id_cliente = a.id_cliente
)

SELECT
    id_contrato, id_cliente, data_ref, cliente_sem_cadastro,

    -- brutas
    estado_civil, tipo_renda, nivel_educacao, ocupacao, tipo_organizacao, tipo_moradia,
    possui_carro, possui_imovel,
    qtd_filhos, qtd_membros_familia, renda_anual,
    nota_regiao_cliente, nota_regiao_cliente_cidade,

    -- derivadas
    idade,
    renda_mensal,
    renda_mensal / qtd_membros_familia                  AS renda_per_capita,
    MIN(1.0, 1.0 * qtd_filhos / qtd_membros_familia)    AS pct_filhos_familia,
    MAX(0, qtd_membros_familia - qtd_filhos)            AS qtd_adultos_familia,
    possui_carro + possui_imovel                        AS score_patrimonio,        -- NULL se algum não for informado
    nota_regiao_cliente - nota_regiao_cliente_cidade    AS diff_nota_regiao,

    -- flags (cliente sem cadastro cai como ausente, porque os campos ficam NULL)
    CASE WHEN renda_anual IS NULL THEN 1 ELSE 0 END                            AS flag_renda_ausente,
    CASE WHEN qtd_membros_familia IS NULL THEN 1 ELSE 0 END                    AS flag_membros_invalido,
    CASE WHEN ocupacao IN ('Não informado', 'Sem cadastro') THEN 1 ELSE 0 END  AS flag_ocupacao_ausente,
    CASE WHEN idade IS NULL THEN 1 ELSE 0 END                                  AS flag_data_nascimento_invalida,

    -- campos ausentes entre os 14 do cadastro (sem cadastro = 14)
    CASE WHEN cliente_sem_cadastro = 1 THEN 14 ELSE
        (estado_civil     = 'Não informado') + (tipo_renda       = 'Não informado')
      + (nivel_educacao   = 'Não informado') + (ocupacao         = 'Não informado')
      + (tipo_organizacao = 'Não informado') + (tipo_moradia     = 'Não informado')
      + (possui_carro IS NULL) + (possui_imovel IS NULL)
      + (qtd_filhos IS NULL) + (qtd_membros_familia IS NULL) + (renda_anual IS NULL)
      + (nota_regiao_cliente IS NULL) + (nota_regiao_cliente_cidade IS NULL)
      + (data_nascimento IS NULL)
    END AS qtd_campos_ausentes
FROM juntado;

