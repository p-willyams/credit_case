WITH tb_emprestimos AS (
    SELECT *
    FROM base_historico_emprestimos
    WHERE status_contrato = 'Aprovado'	 
),

tb_cadastral AS (
    SELECT id_cliente,
        data_nascimento,
        renda_anual,
        CASE WHEN renda_anual IS NULL THEN 1 ELSE 0 END AS flag_renda_ausente,
        1.0 * renda_anual / 12.0 AS renda_mensal_cliente,
        qtd_membros_familia,
        qtd_filhos,
        nota_regiao_cliente - nota_regiao_cliente_cidade AS diff_nota_regiao,
        membros_invalido,
        data_nascimento_invalida,
        CASE WHEN ocupacao IS 'Não informado' THEN 1 ELSE 0 END AS flag_ocupacao_ausente,
        estado_civil,
        tipo_renda,
        nivel_educacao,
        qtd_filhos,
        qtd_membros_familia,
        ocupacao,
        tipo_organizacao,
        tipo_moradia,
        renda_anual,
        CASE WHEN possui_carro IS 'Não' THEN 0 WHEN possui_carro IS 'Não informado' THEN NULL ELSE 1 END AS possui_carro,
        CASE WHEN possui_imovel IS 'Não' THEN 0 WHEN possui_imovel IS 'Não informado' THEN NULL ELSE 1 END AS possui_imovel,
        nota_regiao_cliente,
        nota_regiao_cliente_cidade
    FROM base_cadastral
)

SELECT SUBSTR(t1.data_decisao, 1, 10) AS data_ref,
       t1.id_contrato,
       t1.id_cliente,
       t2.data_nascimento,
       t2.estado_civil,
       t2.tipo_renda,
       t2.ocupacao,
       t2.nota_regiao_cliente,
       t2.nota_regiao_cliente_cidade,
       t2.tipo_organizacao,
       t2.renda_anual,
       t2.possui_carro,
       t2.possui_imovel,
       t2.nivel_educacao,
       t2.qtd_filhos,
       t2.qtd_membros_familia,
       (julianday(t1.data_decisao) - julianday(t2.data_nascimento)) / 365.25 AS idade_cliente,
       t2.renda_mensal_cliente,
       t2.renda_mensal_cliente / t2.qtd_membros_familia AS renda_per_capita,
       1.0 * t2.qtd_filhos / t2.qtd_membros_familia AS pct_filhos_familia,
       t2.qtd_membros_familia - t2.qtd_filhos AS qtd_adultos_familia,
       t2.possui_carro + t2.possui_imovel AS score_patrimonio,
       t2.diff_nota_regiao,
       t2.membros_invalido AS flag_membros_invalidos,
       t2.flag_renda_ausente,
       t2.flag_ocupacao_ausente,
       t2.data_nascimento_invalida,
       t2.flag_renda_ausente + t2.flag_ocupacao_ausente + t2.data_nascimento_invalida AS qtd_ausentes
FROM tb_emprestimos AS t1
LEFT JOIN tb_cadastral AS t2
ON t1.id_cliente = t2.id_cliente
LIMIT 5

