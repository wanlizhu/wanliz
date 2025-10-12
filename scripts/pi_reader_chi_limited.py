#!/usr/bin/env python3
from perfins.PIFGfxReader import *

reader_n1x = PIFGfxReader(r"C:\Users\WanliZhu\Downloads\pi_n1x\.pfm")
reader_emu = PIFGfxReader(r"C:\Users\WanliZhu\Downloads\pi_emu\.pfm")
frame_time_n1x = [-1, -1] # [start, end]
frame_time_emu = [-1, -1] 
metrics_n1x = [""]
metrics_emu = [""]

def get_emu_span_with_name(name):
    index = 0
    for span_emu in reader_emu.getSpanValues("3D0_0"):
        if span_emu["type"] != "Buckets" or int(span_emu["start"]) < frame_time_emu[0]:
            continue 
        if span_emu["name"] == name:
            return span_emu, index
        index += 1
    print(f"Failed to find emu span with name '{name}'")
    return None, None

def get_emu_span_with_index(index):
    index2 = 0
    for span_emu in reader_emu.getSpanValues("3D0_0"):
        if span_emu["type"] != "Buckets" or int(span_emu["start"]) < frame_time_emu[0]:
            continue 
        if index2 == index:
            return span_emu
        index2 += 1
    print(f"Failed to find emu span with index {index}")
    return None 

if frame_time_n1x[0] < 0 or frame_time_emu[0] < 0:
    first_frame_n1x = reader_n1x.getSpanValues("frame_0")[0]
    first_frame_emu = reader_emu.getSpanValues("frame_0")[0]
    frame_time_n1x = [int(first_frame_n1x["start"]), int(first_frame_n1x["end"])]
    frame_time_emu = [int(first_frame_emu["start"]), int(first_frame_emu["end"])]
    duration_n1x = (frame_time_n1x[1] - frame_time_n1x[0]) / 1000000.0
    duration_emu = (frame_time_emu[1] - frame_time_emu[0]) / 1000000.0
    print(f"N1x frame time: {duration_n1x:.2f} ms ({duration_n1x / duration_emu * 100:.2f}% of Emu)")
    print(f"       N1x FPS: {1000.0 / duration_n1x:.2f} ({((1000.0 / duration_n1x) / (1000.0 / duration_emu))* 100:.2f}% of Emu)")
    print(f"Emu frame time: {duration_emu:.2f} ms")
    print(f"       Emu FPS: {1000.0 / duration_emu:.2f}")

x = 0
index_n1x = 0
for span_n1x in reader_n1x.getSpanValues("3D0_0"):
    if span_n1x["type"] != "Buckets" or int(span_n1x["start"]) < frame_time_n1x[0]:
        continue 
    #span_emu = get_emu_span_with_index(index_n1x)
    span_emu, index_emu = get_emu_span_with_name(span_n1x["name"])
    if span_emu is not None:
        #metrics_n1x = reader_n1x.getMetricData(metrics_n1x, timeStart=int(span_n1x["start"]), timeEnd=int(span_n1x["end"]))[0]
        #metrics_emu = reader_emu.getMetricData(metrics_emu, timeStart=int(span_emu["start"]), timeEnd=int(span_emu["end"]))[0]
        duration_n1x = (int(span_n1x["end"]) - int(span_n1x["start"])) / 1000000.0 
        duration_emu = (int(span_emu["end"]) - int(span_emu["start"])) / 1000000.0 
        if span_n1x["name"] == span_emu["name"]:
            print(f"span {index_n1x} has the same name: {index_n1x} -> {index_emu},  {span_n1x["start"] / 1000000.0:.2f} -> {span_emu["start"] / 1000000.0:.2f}")
        else:
            print(f"span {index_n1x}: {span_n1x['name']} -> {span_emu['name']}")
            x += 1
    index_n1x += 1
print(f"Found {x} span with different names")