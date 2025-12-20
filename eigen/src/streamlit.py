import streamlit as st
import pandas as pd
import plotly.express as px

st.set_page_config(page_title="HPC Benchmark Analysis", layout="wide")
st.title("📊 Matrix Solver Performance Dashboard")

@st.cache_data
def load_data():
    df = pd.read_csv("/home/mengelsl/MA-bench-framework/eigen/outputs/perf_20251220_195139/perf_results.csv")
    t1 = df[df['cores'] == 1].groupby(['matrix', 'algorithm'])['real_time_s'].mean().reset_index()
    t1 = t1.rename(columns={'real_time_s': 't1_time'})
    df = df.merge(t1, on=['matrix', 'algorithm'])
    df['speedup'] = df['t1_time'] / df['real_time_s']
    return df

df = load_data()

st.sidebar.header("Filter")
selected_matrix = st.sidebar.multiselect("Matrix wählen", df['matrix'].unique(), default=df['matrix'].unique())
selected_algo = st.sidebar.multiselect("Algorithmus", df['algorithm'].unique(), default=df['algorithm'].unique())

filtered_df = df[(df['matrix'].isin(selected_matrix)) & (df['algorithm'].isin(selected_algo))]

col1, col2 = st.columns(2)

with col1:
    st.subheader("Laufzeit (Real Time)")
    fig_time = px.line(filtered_df, x="cores", y="real_time_s", color="matrix", 
                       line_dash="algorithm", markers=True, log_y=True)
    st.plotly_chart(fig_time, use_container_width=True)

with col2:
    st.subheader("Speedup (Skalierbarkeit)")
    fig_speedup = px.line(filtered_df, x="cores", y="speedup", color="matrix", 
                          line_dash="algorithm", markers=True)
    fig_speedup.add_shape(type="line", x0=1, y0=1, x1=df['cores'].max(), y1=df['cores'].max(),
                          line=dict(color="Gray", dash="dash"))
    st.plotly_chart(fig_speedup, use_container_width=True)

st.subheader("Cache-Effizienz & Hardware-Metriken")
metric = st.selectbox("Metrik wählen", ["cache_misses", "instructions", "cycles"])
fig_metrics = px.bar(filtered_df, x="cores", y=metric, color="matrix", barmode="group")
st.plotly_chart(fig_metrics, use_container_width=True)