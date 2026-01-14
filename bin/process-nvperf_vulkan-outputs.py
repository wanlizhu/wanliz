#!/usr/bin/env python3
import csv
import re
import sys 
from collections import defaultdict


def generate_comparison_in_csv(in_baseline, in_test):
    test_data = []
    with open(in_test, "r") as file_test:
        for line_test in file_test:
            line_test = line_test.strip()
            if not line_test.startswith("["):
                continue 
            test_data.append({
                "name": line_test.split("|")[0].split(" ")[1],
                "value": line_test.split(" = ")[1].split(" ")[0]
            })
    print(f"Found {len(test_data)} test records")
    
    comparison_data = []
    base_records_count = 0
    counterparts_count = 0
    with open(in_baseline, "r") as file_base:
        for line_base in file_base:
            line_base = line_base.strip()
            if not line_base.startswith("["):
                continue 

            name = line_base.split("|")[0].split(" ")[1]
            value_test = "N/A"
            if any(record.get("name") == name for record in test_data):
                test_record = next((record for record in test_data if record.get("name") == name), None)
                value_test = "N/A" if test_record is None else test_record.get("value")

            tags = "|".join(line_base.split(" = ")[0].split("|")[1:])
            value_base = line_base.split(" = ")[1].split(" ")[0]
            value_unit = line_base.split(" ")[-1][0:-1]
            comparison_data.append({
                "Name": name,
                "Tags": tags,
                "Base Value": value_base,
                "Test Value": value_test,
                "Unit": value_unit
            })
            base_records_count += 1
            counterparts_count += 0 if value_test == "N/A" else 1

    print(f"Found {base_records_count} base records ({counterparts_count} counterparts in test records)")

    out_csv_filename = "nvperf_vulkan__base_vs_test.csv"
    column_names = ["Name", "Tags", "Base Value", "Test Value", "Unit"]
    with open(out_csv_filename, "w", newline="", encoding="utf-8") as out_csv_file:
        writer = csv.DictWriter(out_csv_file, fieldnames=column_names)
        writer.writeheader()
        writer.writerows(comparison_data)
    print(f"Generated {out_csv_filename}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(f"Usgae: {sys.argv[0]} <baseline> <test>")
    print(f"Base output: {sys.argv[1]}")
    print(f"Test output: {sys.argv[2]}")
    input("Press [Enter] to continue: ")
    generate_comparison_in_csv(sys.argv[1], sys.argv[2])
