import os
import pandas as pd
import numpy as np
import sqlite3

dir_path = os.path.join("data", "processed")


def limpar_base_cadastral(df):
    """
    Realiza a limpeza e padronização da base_cadastral.
    """
    # Remove duplicidades pelo id_cliente
    df = df.drop_duplicates(subset=["id_cliente"], keep="first").copy()

    # Data de nascimento
    df["data_nascimento"] = pd.to_datetime(
        df["data_nascimento"], format="%Y-%m-%d", errors="coerce"
    )
    df["data_nascimento_invalida"] = df["data_nascimento"].isna().astype(int)

    # Quantidade de membros da família
    df["qtd_membros_familia"] = (
        pd.to_numeric(df["qtd_membros_familia"], errors="coerce").fillna(0).astype(int)
    )
    df["membros_invalido"] = (df["qtd_membros_familia"] == 0).astype(int)
    df.loc[df["qtd_membros_familia"] == 0, "qtd_membros_familia"] = np.nan

    # Renda anual
    df["renda_anual"] = (
        df["renda_anual"]
        .astype(str)
        .replace("não informado", np.nan)
        .str.replace("R$", "", regex=False)
        .str.replace(".", "", regex=False)
        .str.replace(",", ".", regex=False)
        .astype(float)
    )

    # Sexo
    df["sexo"] = (
        df["sexo"]
        .astype(str)
        .str.strip()
        .str.lower()
        .replace(
            {
                "masculino": "Masculino",
                "feminino": "Feminino",
                "não informado": "Não informado",
            }
        )
    )
    df.loc[~df["sexo"].isin(["Masculino", "Feminino", "Não informado"]), "sexo"] = (
        "Não informado"
    )

    # Tipo de renda
    df["tipo_renda"] = df["tipo_renda"].replace(
        ["ASSALARIADO", "assalariado", "Assalariado"], "Assalariado"
    )
    df["tipo_renda"] = df["tipo_renda"].replace(
        ["AUTONOMO", "Autonomo", "autonomo", "Autônomo", "autônomo"], "Autônomo"
    )

    # Possui carro
    df["possui_carro"] = (
        df["possui_carro"]
        .astype(str)
        .str.strip()
        .str.lower()
        .replace(
            {"sim": "Sim", "não": "Não", "nao": "Não", "não informado": "Não informado"}
        )
    )
    df.loc[
        ~df["possui_carro"].isin(["Sim", "Não", "Não informado"]), "possui_carro"
    ] = "Não informado"

    # Possui imóvel
    df["possui_imovel"] = (
        df["possui_imovel"]
        .astype(str)
        .str.strip()
        .str.lower()
        .replace(
            {"sim": "Sim", "não": "Não", "nao": "Não", "não informado": "Não informado"}
        )
    )
    df.loc[
        ~df["possui_imovel"].isin(["Sim", "Não", "Não informado"]), "possui_imovel"
    ] = "Não informado"

    # Ocupação
    df.loc[df["ocupacao"].isnull() & (df["tipo_renda"] == "Aposentado"), "ocupacao"] = (
        "Aposentado"
    )
    df.loc[
        df["ocupacao"].isnull() & (df["tipo_renda"] == "Desempregado"), "ocupacao"
    ] = "Sem Ocupação"
    df["ocupacao"] = df["ocupacao"].fillna("Não informado")

    return df


def limpar_base_historico_emprestimos(df):
    df = df.copy()
    # Adiciona lógica do notebook: remover ids explícitos
    ids_para_remover = [
        1615022,
        1419696,
        1836151,
        1685204,
        1230966,
        2507738,
        2134669,
        1127559,
        1190415,
        2682600,
        1614732,
        1886607,
        2643672,
        1698122,
        1294026,
        1535711,
        1584492,
        1131374,
        2246656,
        2508742,
        2242722,
        2580658,
        2122990,
        2560369,
        2776552,
        1242551,
        2803854,
        1390967,
        1712122,
        2567534,
        2200180,
        2368730,
        1937477,
        1643234,
        2044690,
        2165183,
        1442414,
        2505129,
        1132251,
        2314126,
        1629949,
        2800721,
        1866161,
        1459347,
        1705289,
        2075475,
        1056978,
        1446972,
        1311657,
        1065461,
        2424948,
        1424760,
        2273951,
        1522867,
        1078867,
        1209334,
        2687356,
        1158924,
        1839214,
        1613780,
        1905656,
        1550142,
        1785207,
        2729041,
        1283598,
        2693606,
        1362928,
        1152717,
        1060378,
        2327516,
        2495732,
        1797495,
        1270577,
        1816279,
        1726666,
        2353284,
        1101835,
        2818917,
        1201344,
        1430190,
        1999858,
        1442782,
        2841235,
        2391145,
        1951763,
        2371508,
        1041864,
        2108388,
        1519540,
        1157856,
        1509687,
        2095643,
        1743079,
        1829792,
        2480557,
        1368974,
        2729586,
        1332651,
        1837337,
        1451442,
        2641112,
        1994189,
        1431973,
        1849112,
        1724139,
        2299626,
        2095926,
        2063537,
        1294531,
        1619866,
        1370124,
        1522856,
        1887498,
        1865325,
        2677097,
        1502004,
        1940719,
        1560281,
        2239028,
        1308032,
        2148711,
        1499065,
        1012137,
        2509505,
        2182814,
        1256415,
        2094723,
        1927003,
        2290688,
        1102002,
        2208654,
        2073924,
        1492883,
        1460240,
        1179460,
        1871923,
        2780381,
        2831674,
        2142836,
        2260327,
        2318105,
        1956183,
        1523243,
        2716758,
        2262826,
        1765405,
        2706448,
        2241944,
        1340616,
        1693909,
        2137092,
        1921357,
        1406579,
        2249660,
        1448508,
        2498826,
        2517646,
        1740952,
        1487778,
        1735850,
        2450596,
        2071178,
        2237896,
        2774362,
        2712892,
        1147230,
        2323726,
        1915840,
        2166584,
        2237877,
        1010961,
        1648756,
        1077690,
        2749241,
        1221100,
        2458183,
        1360468,
        2652099,
        2329129,
        1797481,
        1856898,
        2084965,
        1829540,
        2725712,
        2087298,
        2362194,
        2617483,
        2053182,
        1417504,
        1032758,
        2029141,
        2426767,
        2290406,
        1183455,
        2418752,
        2022818,
        1020350,
        2102467,
        2208054,
        1729522,
        2382784,
        1332454,
        1000648,
        1452696,
        1548479,
        1912496,
        2507796,
        1136181,
        1417440,
        1817937,
        1748215,
        2797298,
        2610961,
        2077440,
        1435480,
        1539266,
        1895650,
        2552450,
        1111123,
        2120712,
        2499612,
        2845509,
        2846404,
        2846871,
        2847162,
        2847802,
        2848176,
        2850346,
        2850695,
        2851099,
        2852198,
        2852473,
        2853210,
        2856002,
        2856308,
        2856438,
        2856939,
        2857097,
        2858059,
        2858212,
        2859583,
        2860001,
        2860763,
        2861223,
        2861340,
        2862414,
        2862513,
        2863390,
        2864051,
        2864804,
        2865275,
        2866749,
        2866985,
        2867999,
        2870258,
    ]
    df = df[~df["id_contrato"].isin(ids_para_remover)].reset_index(drop=True)

    # Conversão de datas
    colunas_data = [
        "data_decisao",
        "data_primeiro_vencimento",
        "data_ultimo_vencimento_original",
        "data_ultimo_vencimento",
        "data_encerramento",
    ]
    for c in colunas_data:
        df[c] = pd.to_datetime(df[c], errors="coerce")
    df["hora_solicitacao"] = pd.to_datetime(
        df["hora_solicitacao"], format="%H:%M:%S", errors="coerce"
    ).dt.time

    # Área de venda - flag de ausente e padronização
    df["area_venda_sem_area"] = (df["area_venda"] == -1).astype(int)
    df["area_venda"] = df["area_venda"].astype(str).replace("-1", "Sem área")

    # Padronização do tipo_contrato
    mapa = {
        "crédito rotativo": "Crédito Rotativo",
        "credito rotativo": "Crédito Rotativo",
        "empréstimo em dinheiro": "Empréstimo em Dinheiro",
        "emprestimo em dinheiro": "Empréstimo em Dinheiro",
        "financiamento de consumo": "Financiamento de Consumo",
    }
    df["tipo_contrato"] = (
        df["tipo_contrato"].astype(str).str.strip().str.lower().map(mapa)
    )
    assert df["tipo_contrato"].notna().all()

    # valor_bem zerado e categoria válida diferente de não se aplica/não informado → nan
    mascara_bem_invalido = (
        (df["valor_bem"] == 0)
        & df["categoria_bem"].notnull()
        & ~df["categoria_bem"]
        .astype(str)
        .str.lower()
        .str.contains(
            "não se aplica|nao se aplica|não informado|nao informado", na=False
        )
    )
    df.loc[mascara_bem_invalido, "valor_bem"] = np.nan

    # Zerados de parcelas/valor solicitado em contratos aprovados
    mascara_aprovado_zero_parcelas = (df["qtd_parcelas_planejadas"] == 0) & (
        df["status_contrato"] == "Aprovado"
    )
    df.loc[mascara_aprovado_zero_parcelas, "qtd_parcelas_planejadas"] = np.nan

    mascara_aprovado_zero_valor_solicitado = (df["valor_solicitado"] == 0) & (
        df["status_contrato"] == "Aprovado"
    )
    df.loc[mascara_aprovado_zero_valor_solicitado, "valor_solicitado"] = np.nan

    # Flags de inconsistência em contratos aprovados
    aprov = df["status_contrato"] == "Aprovado"
    df["prazo_ausente"] = (aprov & (df["qtd_parcelas_planejadas"] == 0)).astype(int)
    df["solicitado_ausente"] = (aprov & (df["valor_solicitado"] == 0)).astype(int)
    df["credito_invalido"] = (aprov & (df["valor_credito"] == 0)).astype(int)
    df["parcela_invalida"] = (aprov & (df["valor_parcela"] == 0)).astype(int)
    df["bem_invalido"] = mascara_bem_invalido.astype(int)

    # Ajusta nulos baseando-se nas flags
    df.loc[df["prazo_ausente"] == 1, "qtd_parcelas_planejadas"] = np.nan
    df.loc[df["solicitado_ausente"] == 1, "valor_solicitado"] = np.nan
    df.loc[df["credito_invalido"] == 1, "valor_credito"] = np.nan
    df.loc[df["parcela_invalida"] == 1, "valor_parcela"] = np.nan
    df.loc[df["bem_invalido"] == 1, "valor_bem"] = np.nan

    return df


def limpar_base_historico_parcelas(df):
    # Adiciona lógica do notebook: remover ids explícitos
    ids_para_remover = [
        1615022,
        1419696,
        1836151,
        1685204,
        1230966,
        2507738,
        2134669,
        1127559,
        1190415,
        2682600,
        1614732,
        1886607,
        2643672,
        1698122,
        1294026,
        1535711,
        1584492,
        1131374,
        2246656,
        2508742,
        2242722,
        2580658,
        2122990,
        2560369,
        2776552,
        1242551,
        2803854,
        1390967,
        1712122,
        2567534,
        2200180,
        2368730,
        1937477,
        1643234,
        2044690,
        2165183,
        1442414,
        2505129,
        1132251,
        2314126,
        1629949,
        2800721,
        1866161,
        1459347,
        1705289,
        2075475,
        1056978,
        1446972,
        1311657,
        1065461,
        2424948,
        1424760,
        2273951,
        1522867,
        1078867,
        1209334,
        2687356,
        1158924,
        1839214,
        1613780,
        1905656,
        1550142,
        1785207,
        2729041,
        1283598,
        2693606,
        1362928,
        1152717,
        1060378,
        2327516,
        2495732,
        1797495,
        1270577,
        1816279,
        1726666,
        2353284,
        1101835,
        2818917,
        1201344,
        1430190,
        1999858,
        1442782,
        2841235,
        2391145,
        1951763,
        2371508,
        1041864,
        2108388,
        1519540,
        1157856,
        1509687,
        2095643,
        1743079,
        1829792,
        2480557,
        1368974,
        2729586,
        1332651,
        1837337,
        1451442,
        2641112,
        1994189,
        1431973,
        1849112,
        1724139,
        2299626,
        2095926,
        2063537,
        1294531,
        1619866,
        1370124,
        1522856,
        1887498,
        1865325,
        2677097,
        1502004,
        1940719,
        1560281,
        2239028,
        1308032,
        2148711,
        1499065,
        1012137,
        2509505,
        2182814,
        1256415,
        2094723,
        1927003,
        2290688,
        1102002,
        2208654,
        2073924,
        1492883,
        1460240,
        1179460,
        1871923,
        2780381,
        2831674,
        2142836,
        2260327,
        2318105,
        1956183,
        1523243,
        2716758,
        2262826,
        1765405,
        2706448,
        2241944,
        1340616,
        1693909,
        2137092,
        1921357,
        1406579,
        2249660,
        1448508,
        2498826,
        2517646,
        1740952,
        1487778,
        1735850,
        2450596,
        2071178,
        2237896,
        2774362,
        2712892,
        1147230,
        2323726,
        1915840,
        2166584,
        2237877,
        1010961,
        1648756,
        1077690,
        2749241,
        1221100,
        2458183,
        1360468,
        2652099,
        2329129,
        1797481,
        1856898,
        2084965,
        1829540,
        2725712,
        2087298,
        2362194,
        2617483,
        2053182,
        1417504,
        1032758,
        2029141,
        2426767,
        2290406,
        1183455,
        2418752,
        2022818,
        1020350,
        2102467,
        2208054,
        1729522,
        2382784,
        1332454,
        1000648,
        1452696,
        1548479,
        1912496,
        2507796,
        1136181,
        1417440,
        1817937,
        1748215,
        2797298,
        2610961,
        2077440,
        1435480,
        1539266,
        1895650,
        2552450,
        1111123,
        2120712,
        2499612,
        2845509,
        2846404,
        2846871,
        2847162,
        2847802,
        2848176,
        2850346,
        2850695,
        2851099,
        2852198,
        2852473,
        2853210,
        2856002,
        2856308,
        2856438,
        2856939,
        2857097,
        2858059,
        2858212,
        2859583,
        2860001,
        2860763,
        2861223,
        2861340,
        2862414,
        2862513,
        2863390,
        2864051,
        2864804,
        2865275,
        2866749,
        2866985,
        2867999,
        2870258,
    ]
    df = df[~df["id_contrato"].isin(ids_para_remover)].reset_index(drop=True)

    # Remove duplicatas
    df = df.drop_duplicates().copy()

    # Ajusta tipos e datas
    df["versao_parcela"] = pd.to_numeric(df["versao_parcela"], errors="coerce").astype(
        int
    )
    for c in ["data_prevista_pagamento", "data_real_pagamento"]:
        if c in df.columns:
            df[c] = pd.to_datetime(df[c], errors="coerce")

    chave = ["id_contrato", "numero_parcela"]

    # Ordena e calcula flag de múltiplas versões por parcela
    df = df.sort_values(chave + ["versao_parcela"])
    n_versoes = df.groupby(chave)["versao_parcela"].transform("nunique")
    df["parcela_multiversao"] = (n_versoes > 1).astype(int)

    # Tabela dívidas: uma linha por parcela
    divida = df.groupby(chave, as_index=False).agg(
        id_cliente=("id_cliente", "last"),
        versao_parcela=("versao_parcela", "last"),
        data_prevista_pagamento=("data_prevista_pagamento", "last"),
        valor_previsto_parcela=("valor_previsto_parcela", "last"),
        parcela_multiversao=("parcela_multiversao", "max"),
    )
    divida["previsto_invalido"] = (divida["valor_previsto_parcela"] <= 0).astype(int)

    # Tabela pagamentos: uma linha por evento de pagamento
    pagamentos = (
        df.dropna(subset=["data_real_pagamento"])[
            chave + ["data_real_pagamento", "valor_pago_parcela"]
        ]
        .drop_duplicates()
        .sort_values(chave + ["data_real_pagamento"])
        .reset_index(drop=True)
    )
    pagamentos["pago_acum"] = pagamentos.groupby(chave)["valor_pago_parcela"].cumsum()

    # Resumo por parcela: data quitação e excesso
    p = pagamentos.merge(
        divida[chave + ["valor_previsto_parcela"]], on=chave, how="left"
    )
    valido = p["valor_previsto_parcela"] > 0

    quit_ = (
        p[valido & (p["pago_acum"] >= 0.99 * p["valor_previsto_parcela"])]
        .groupby(chave)["data_real_pagamento"]
        .min()
        .rename("data_quitacao")
    )
    tot = pagamentos.groupby(chave)["valor_pago_parcela"].sum().rename("pago_total")

    divida = divida.merge(quit_, on=chave, how="left").merge(tot, on=chave, how="left")
    divida["pago_com_encargo"] = (
        (divida["pago_total"] > 1.02 * divida["valor_previsto_parcela"])
        & (divida["valor_previsto_parcela"] > 0)
    ).astype(int)

    # Pagamento acumulado limitado ao previsto
    pagamentos = pagamentos.merge(
        divida[chave + ["valor_previsto_parcela"]], on=chave, how="left"
    )
    pagamentos["pago_acum_cap"] = np.minimum(
        pagamentos["pago_acum"], pagamentos["valor_previsto_parcela"]
    )

    divida["encargo"] = (divida["pago_total"] - divida["valor_previsto_parcela"]).clip(
        lower=0
    )

    return divida, pagamentos


def main():
    # Leitura dos dados brutos
    base_cadastral = pd.read_parquet("data/raw/base_cadastral.parquet")
    base_historico_parcelas = pd.read_parquet("data/raw/historico_parcelas.parquet")
    base_historico_emprestimos = pd.read_parquet(
        "data/raw/historico_emprestimos.parquet"
    )

    # Processamento/limpeza
    base_cadastral_limpa = limpar_base_cadastral(base_cadastral)
    base_historico_emprestimos_limpa = limpar_base_historico_emprestimos(
        base_historico_emprestimos
    )
    base_dividas_limpa, base_pagamentos_limpa = limpar_base_historico_parcelas(
        base_historico_parcelas
    )

    bases_limpas = {
        "base_cadastral": base_cadastral_limpa,
        "base_dividas": base_dividas_limpa,
        "base_pagamentos": base_pagamentos_limpa,
        "base_historico_emprestimos": base_historico_emprestimos_limpa,
    }

    db_path = os.path.join(dir_path, "database.db")
    os.makedirs(dir_path, exist_ok=True)

    with sqlite3.connect(db_path) as conn:
        for nome_tabela, df in bases_limpas.items():
            df.to_sql(nome_tabela, conn, if_exists="replace", index=False)
            print(f"Tabela '{nome_tabela}' criada com sucesso com os dados limpos.")


if __name__ == "__main__":
    main()
