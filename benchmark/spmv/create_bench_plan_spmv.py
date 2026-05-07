import pandas as pd
import numpy as np

input_file = "itertest.csv"
output_file = "bench_plan.csv"
goal_time = 10
df = pd.read_csv(input_file)

df["Iter_Target"] = ((df["Iterations"] / df["Runtime"]) * goal_time).round().astype(int)

plan_data = []
for _, row in df.iterrows():
    plan_data.append(row[["Matrix", "Cores", "NUMA_Policy", "Iter_Target"]].tolist())

plan_df = pd.DataFrame(plan_data, columns=["Matrix", "Cores", "NUMA_Policy", "Iter_Target"])
plan_df.to_csv(output_file, index=False)

print("Bench plan created and saved.")
