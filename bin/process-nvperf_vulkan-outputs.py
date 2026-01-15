#!/usr/bin/env python3
import csv
import re
import sys 
from collections import defaultdict
from decimal import Decimal

def get_value_of_test(test_data_dict, index, name):
    value = "N/A"
    if any(record.get("name") == name for record in test_data_dict[index]):
        test_record = next((record for record in test_data_dict[index] if record.get("name") == name), None)
        value = "N/A" if test_record is None else test_record.get("value")
        value = Decimal(value)
    return value

def percentage_of_test_vs_base(out_record, index):
    test_value = out_record.get(f"Test-{index} Value")
    base_value = out_record.get("Base Value")
    percentage = (Decimal(test_value) / Decimal(base_value)) * Decimal(100)
    return f"{percentage:.2f}%"

def generate_comparison_in_csv(in_baseline, in_tests: list):
    test_data_dict = defaultdict(list)
    for i, test in enumerate(in_tests, start=1):
        with open(test, "r") as file_test:
            for line_test in file_test:
                line_test = line_test.strip()
                if not line_test.startswith("["):
                    continue 
                test_data_dict[i].append({
                    "name": line_test.split("|")[0].split(" ")[1],
                    "value": line_test.split(" = ")[1].split(" ")[0]
                })
        print(f"Found {len(test_data_dict[i])} records in test {i}")
    
    comparison_data = []
    with open(in_baseline, "r") as file_base:
        for line_base in file_base:
            line_base = line_base.strip()
            if not line_base.startswith("["):
                continue 
            name = line_base.split("|")[0].split(" ")[1]
            out_record = {
                "Test Case": name,
                "Tags": "|".join(line_base.split(" = ")[0].split("|")[1:]),
                "Base Value": format(Decimal(line_base.split(" = ")[1].split(" ")[0]), "f"),
                "Unit": line_base.split(" ")[-1][0:-1]
            }
            for i in range(1, len(test_data_dict) + 1):
                out_record[f"Test-{i} Value"] = format(Decimal(get_value_of_test(test_data_dict, i, name)), "f")
                out_record[f"Test-{i} vs Base"] = percentage_of_test_vs_base(out_record, i)
            comparison_data.append(out_record)
    print(f"Found {len(comparison_data)} base records")

    out_csv_filename = "nvperf_vulkan__base_vs_test.csv"
    column_names = ["Test Case", "Tags", "Base Value"]
    for i in range(1, len(test_data_dict) + 1):
        column_names.append(f"Test-{i} Value")
        column_names.append(f"Test-{i} vs Base")
    column_names.append("Unit")
    with open(out_csv_filename, "w", newline="", encoding="utf-8") as out_csv_file:
        writer = csv.DictWriter(out_csv_file, fieldnames=column_names)
        writer.writeheader()
        writer.writerows(comparison_data)
    print(f"Generated {out_csv_filename}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(f"Usgae: {sys.argv[0]} <baseline> <test1> [test2]")
    
    print(f"  Base output: {sys.argv[1]}")
    for i, test in enumerate(sys.argv[2:], start=1):
        print(f"Test {i} output: {test}")
    input("Press [Enter] to continue: ")

    generate_comparison_in_csv(sys.argv[1], sys.argv[2:])
