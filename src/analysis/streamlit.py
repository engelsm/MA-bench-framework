import streamlit as st
import pandas as pd
import plotly.express as px

st.set_page_config(page_title="HPC Benchmark Analysis", layout="wide")
st.title("📊 Spectra OMP Performance Dashboard")

@st.cache_data
def load_data():
    # Pfad ggf. anpassen oder dynamisch laden
    csv_path = "/home/mengelsl/MA-bench-framework/eigen/outputs/perf_20251221_165228/perf_results.csv"
    df = pd.read_csv(csv_path)
    
    # Konvertierung: Nanosekunden in Sekunden für bessere Lesbarkeit
    df['walltime_s'] = df['perf_walltime_ns'] / 1e9
    
    # Speedup Berechnung basierend auf walltime_s
    # Wir nehmen den Mittelwert der Runs für T1 (Single Core)
    t1 = df[df['n_cores'] == 1].groupby(['matrix_path', 'algorithm'])['walltime_s'].mean().reset_index()
    t1 = t1.rename(columns={'walltime_s': 't1_time'})
    
    df = df.merge(t1, on=['matrix_path', 'algorithm'])
    df['speedup'] = df['t1_time'] / df['walltime_s']
    
    # Effizienz-Metrik: Instructions per Cycle (IPC)
    df['IPC'] = df['perf_instructions'] / df['perf_cycles']
    
    return df

try:
    df = load_data()

    # --- Sidebar Filter ---
    st.sidebar.header("Filter")
    selected_matrix = st.sidebar.multiselect(
        "Matrix wählen", 
        df['matrix_path'].unique(), 
        default=df['matrix_path'].unique()
    )
    selected_algo = st.sidebar.multiselect(
        "Algorithmus", 
        df['algorithm'].unique(), 
        default=df['algorithm'].unique()
    )

    filtered_df = df[(df['matrix_path'].isin(selected_matrix)) & (df['algorithm'].isin(selected_algo))]

    # --- Row 1: Laufzeit & Speedup ---
    col1, col2 = st.columns(2)

    with col1:
        st.subheader("⏱ Gesamtlaufzeit (Walltime)")
        fig_time = px.line(filtered_df, x="n_cores", y="walltime_s", color="matrix_path", 
                           line_dash="algorithm", markers=True, log_y=True,
                           labels={"walltime_s": "Zeit (s)", "n_cores": "Kerne"})
        st.plotly_chart(fig_time, use_container_width=True)

    with col2:
        st.subheader("🚀 Speedup (Skalierbarkeit)")
        fig_speedup = px.line(filtered_df, x="n_cores", y="speedup", color="matrix_path", 
                              line_dash="algorithm", markers=True,
                              labels={"speedup": "Speedup (x-fach)", "n_cores": "Kerne"})
        # Ideale Linie hinzufügen
        fig_speedup.add_shape(type="line", x0=1, y0=1, x1=df['n_cores'].max(), y1=df['n_cores'].max(),
                              line=dict(color="Gray", dash="dash"))
        st.plotly_chart(fig_speedup, use_container_width=True)

    # --- Row 2: Internes Timing (SpMV vs Management) ---
    st.divider()
    st.subheader("🔍 Internes Timing: SpMV vs. Management")
    
    # Daten für gestapeltes Balkendiagramm schmelzen
    internal_melt = filtered_df.melt(id_vars=['n_cores', 'algorithm', 'matrix_path'], 
                                     value_vars=['intern_spmvtime_s', 'intern_mgmttime_s'],
                                     var_name='Component', value_name='Time_s')
    
    fig_internal = px.bar(internal_melt, x="n_cores", y="Time_s", color="Component", 
                          facet_col="matrix_path", barmode="stack",
                          labels={"Time_s": "Zeit (s)", "n_cores": "Kerne"})
    st.plotly_chart(fig_internal, use_container_width=True)

    # --- Row 3: Hardware Metriken ---
    st.divider()
    st.subheader("📊 Hardware-Level Metriken")
    metric_choice = st.selectbox("Metrik wählen", 
                                ["perf_cache_misses", "IPC", "perf_instructions", "perf_cycles"])
    
    fig_metrics = px.box(filtered_df, x="n_cores", y=metric_choice, color="algorithm",
                         points="all", title=f"{metric_choice} über verschiedene Kerne")
    st.plotly_chart(fig_metrics, use_container_width=True)

    # --- Data Table ---
    if st.checkbox("Rohdaten anzeigen"):
        st.write(filtered_df)

except FileNotFoundError:
    st.error(f"CSV Datei nicht gefunden. Bitte Pfad prüfen!")