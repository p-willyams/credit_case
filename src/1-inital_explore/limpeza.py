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
