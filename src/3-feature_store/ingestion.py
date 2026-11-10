import sqlite3
import pandas as pd


def load_query(file_name, connection):
    with open(f"{file_name}.sql", "r", encoding="utf-8") as file:
        query = file.read()
    return pd.read_sql_query(query, connection)


queries = [
    "fs_exposicao_ativa",
    "fs_cadastral",
    "fs_capacidade_pagamento",
    "fs_contrato_atual",
    "fs_historico_contratos",
    "fs_historico_deliquencia",
    "fs_mapeamento_financeiro",
]


conn = sqlite3.connect("data/processed/database.db")
try:
    dfs = {q: load_query(q, conn) for q in queries}
finally:
    conn.close()


fs_exposicao_ativa = dfs["fs_exposicao_ativa"]
fs_cadastral = dfs["fs_cadastral"]
fs_capacidade_pagamento = dfs["fs_capacidade_pagamento"]
fs_contrato_atual = dfs["fs_contrato_atual"]
fs_historico_contratos = dfs["fs_historico_contratos"]
fs_historico_deliquencia = dfs["fs_historico_deliquencia"]
fs_mapeamento_financeiro = dfs["fs_mapeamento_financeiro"]

conn_fs = sqlite3.connect("data/processed/feature_store.db")
try:
    for name, df in dfs.items():
        df.to_sql(name, conn_fs, if_exists="replace", index=False)
finally:
    conn_fs.close()
