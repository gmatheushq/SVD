"""
Gera um gráfico separado para cada métrica numérica do CSV,
destacando os pontos em k = 123, 173, 210, 247.

Uso:
    python plot_metricas.py

Ajuste as variáveis CSV_PATH, PONTOS_K e SAIDA_DIR conforme necessário.
"""

import os
import pandas as pd
import matplotlib.pyplot as plt

CSV_PATH = "metricas.csv"      
SEP = ";"                    
COL_K = "k"                   
COL_TIPO = "Tipo"              
PONTOS_K = [44, 62, 75, 89] 
SAIDA_DIR = "graficos"         
COLUNAS_IGNORAR = ["Tipo"]     

PONTO_PSNR_EXTRA = {"PB": 636, "RGB": 637}

FONT_LABEL = 15
FONT_TITLE = 17
FONT_LEGEND = 13
FONT_TICKS = 13
def carregar_dados(csv_path: str, sep: str) -> pd.DataFrame:
    df = pd.read_csv(csv_path, sep=sep)
    df.columns = [c.strip() for c in df.columns]
    return df


def obter_metricas(df: pd.DataFrame, col_k: str, ignorar: list) -> list:
    """Retorna todas as colunas numéricas, exceto k e as ignoradas."""
    candidatas = [c for c in df.columns if c != col_k and c not in ignorar]
    numericas = [c for c in candidatas if pd.api.types.is_numeric_dtype(df[c])]
    return numericas


def obter_tipo(df: pd.DataFrame, col_tipo: str) -> str:
    """Identifica o tipo da imagem (PB, RGB, etc.) a partir da coluna Tipo."""
    if col_tipo not in df.columns:
        return ""
    valores = df[col_tipo].dropna().unique()
    if len(valores) == 0:
        return ""
    if len(valores) > 1:
        print(f"[Aviso] Mais de um valor em '{col_tipo}': {list(valores)}. Usando '{valores[0]}'.")
    return str(valores[0])


def obter_ponto_extra_psnr(tipo: str):
    """Retorna o k extra a destacar no PSNR, de acordo com o tipo (PB ou RGB)."""
    tipo_upper = tipo.upper()
    if "PB" in tipo_upper:
        return PONTO_PSNR_EXTRA["PB"]
    if "RGB" in tipo_upper:
        return PONTO_PSNR_EXTRA["RGB"]
    return None


def formatar_valor(valor: float) -> str:
    """Formata o valor da métrica no padrão brasileiro (vírgula decimal, 3 casas)."""
    return f"{valor:.3f}".replace(".", ",")


CORES_PONTOS = ["red", "orange", "green", "purple", "brown", "magenta", "black"]


def plotar_metrica(df: pd.DataFrame, col_k: str, metrica: str,
                    pontos_k: list, saida_dir: str, tipo: str):
    fig, ax = plt.subplots(figsize=(9, 5.5))
    ax.plot(df[col_k], df[metrica], color="#1f77b4", linewidth=1.6, label=metrica)

    encontrados = []
    for i, k_alvo in enumerate(pontos_k):
        linha = df[df[col_k] == k_alvo]
        if linha.empty:
            continue
        cor = CORES_PONTOS[i % len(CORES_PONTOS)]
        valor = linha[metrica].iloc[0]
        ax.scatter(
            linha[col_k],
            linha[metrica],
            color=cor,
            zorder=5,
            s=25,
            label=f"k={k_alvo} = {formatar_valor(valor)}"
        )
        encontrados.append(k_alvo)

    if metrica == "PSNR_dB":
        k_extra = obter_ponto_extra_psnr(tipo)
        if k_extra is not None:
            linha = df[df[col_k] == k_extra]
            if not linha.empty:
                valor = linha[metrica].iloc[0]
                ax.scatter(
                    linha[col_k],
                    linha[metrica],
                    color="black",
                    marker="o",
                    s=35,
                    zorder=6,
                    label=f"k={k_extra} = {formatar_valor(valor)}"
                )
            else:
                print(f"[Aviso] k={k_extra} não encontrado para PSNR (tipo='{tipo}').")
        else:
            print(f"[Aviso] Tipo '{tipo}' não reconhecido (esperado 'PB' ou 'RGB'); nenhum ponto extra de PSNR adicionado.")

    faltando = set(pontos_k) - set(encontrados)
    if faltando:
        print(
            f"[Aviso] k={sorted(faltando)} não encontrado(s) para a métrica '{metrica}'."
        )

    ax.set_xlabel(col_k, fontsize=FONT_LABEL)
    ax.set_ylabel(metrica, fontsize=FONT_LABEL)
    titulo = f"{metrica} em função de {col_k}"
    if tipo:
        titulo += f" ({tipo})"
    ax.set_title(titulo, fontsize=FONT_TITLE)
    ax.tick_params(axis="both", labelsize=FONT_TICKS)
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=FONT_LEGEND)
    fig.tight_layout()

    os.makedirs(saida_dir, exist_ok=True)
    nome_arquivo = f"{metrica}_{tipo}.png" if tipo else f"{metrica}.png"
    caminho_saida = os.path.join(saida_dir, nome_arquivo)
    fig.savefig(caminho_saida, dpi=150)
    plt.close(fig)
    print(f"Gráfico salvo em: {caminho_saida}")


def main():
    df = carregar_dados(CSV_PATH, SEP)
    metricas = obter_metricas(df, COL_K, COLUNAS_IGNORAR)
    tipo = obter_tipo(df, COL_TIPO)

    if not metricas:
        print("Nenhuma coluna numérica encontrada para plotar.")
        return

    print(f"Métricas encontradas: {metricas}")
    print(f"Tipo identificado: {tipo or '(nenhum)'}")
    for metrica in metricas:
        plotar_metrica(df, COL_K, metrica, PONTOS_K, SAIDA_DIR, tipo)


if __name__ == "__main__":
    main()
