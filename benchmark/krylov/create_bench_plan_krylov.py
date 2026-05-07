import pandas as pd
import numpy as np

input_file = "itertest.csv"
df = pd.read_csv(input_file)

goal_time = 10

df["Time_per_Op"] = (df["SpMV_Time"]+df["Mgmt_Time"]) / df["N_OPS"]
df["Target_Ops"] = goal_time / df["Time_per_Op"]

plan_data = []

for _, row in df.iterrows():
    matrix = row["Matrix"]
    cores = int(row["Cores"])
    numa = row["NUMA_Policy"]
    algo = row["Algo"]
    
    scaling_factor = df["Target_Ops"].iloc[_] / row["N_OPS"]
    
    new_arg1 = int(max(1, row["Arg1"] * scaling_factor))
    
    arg2 = int(row["Arg2"])
    arg3 = int(row["Arg3"])

    plan_data.append([
        matrix, 
        cores, 
        numa,
        algo, 
        new_arg1, 
        arg2, 
        arg3
    ])

plan_df = pd.DataFrame(plan_data, columns=["Matrix", "Cores", "NUMA_Policy", "Algo", "Arg1", "Arg2", "Arg3"])

plan_df.to_csv("bench_plan.csv", index=False)

print(f"Bench plan with {len(plan_df)} test runs created and saved to 'bench_plan.csv'.")