#!/usr/bin/env python3
from perfins.PIFGfxReader import *

class N1x_CHI_limiter:
    def compare(self, n1x_report, emu_report):
        self.n1x_report = n1x_report
        self.emu_report = emu_report 

    def get_perf_impact(self):
        pass 

    def __align_first_frame(self):
        pass 

    def __is_n1x_bucket_CHI_limited(self):
        pass 

    def __load_n1x_bucket_metrics(self):
        n1x_metric_names = [
            '06_MMU_limited', '07_RASTER_limited', '08_Rop_limited', '10_GCC_limited',
            '11_LTC_limited', '12_LST_limited', '13_TTU_limited', '14_SM_limited',
            '16_Launch_pipe_limited', '17_HSHUB_limited', 
            'DRAM_limited', 'HSHUB_limited', 'LTC_limited', 
            'HSHUB___DRAM_GB_per_s', 'HSHUB___read_bytes', 'HSHUB___write_bytes',
            'ltc_chi_cmd_out_ReadNoSnp_fbp{FBP}_ltc{LTC}_l2slice{L2SLICE}',
            'ltc_chi_cmd_out_WriteNoSnpPartial_fbp{FBP}_ltc{LTC}_l2slice{L2SLICE}',
            'ltc_chi_cmd_out_WriteNoSnpFull_fbp{FBP}_ltc{LTC}_l2slice{L2SLICE}'
        ]

    def __load_emu_bucket_metrics(self):
        emu_metric_names = [
            '02_PCIe_limited', '03_SYSLTC_limited', '06_MMU_limited', '07_RASTER_limited', 
            '08_Rop_limited', '10_GCC_limited', '11_LTC_limited', '12_LST_limited',
            '13_TTU_limited', '14_SM_limited', '15_FB_limited', '16_Launch_pipe_limited',
            'FB_limited', 'LTC_limited', 'SYSLTC_limited', 'FB___bytesPerClk'
        ]

        

# N1x: Horizon6
# Emu: GB203-as-T254 (Emulation)
reader_n1x = PIFGfxReader(r"C:\Users\WanliZhu\Downloads\pi_n1x\.pfm")
reader_emu = PIFGfxReader(r"C:\Users\WanliZhu\Downloads\pi_emu\.pfm")
frame_time_n1x = [-1, -1] # [start, end]
frame_time_emu = [-1, -1] 
metric_names_n1x = [
    '06_MMU_limited',
    '07_RASTER_limited',
    '08_Rop_limited',
    '10_GCC_limited',
    '11_LTC_limited',
    '12_LST_limited',
    '13_TTU_limited',
    '14_SM_limited',
    '16_Launch_pipe_limited',
    '17_HSHUB_limited',
    'DRAM_limited',
    'HSHUB_limited',
    'LTC_limited',
    'HSHUB___DRAM_GB_per_s', 
    'HSHUB___read_bytes',
    'HSHUB___write_bytes',
    'ltc_chi_cmd_out_ReadNoSnp_fbp{FBP}_ltc{LTC}_l2slice{L2SLICE}',
    'ltc_chi_cmd_out_WriteNoSnpPartial_fbp{FBP}_ltc{LTC}_l2slice{L2SLICE}',
    'ltc_chi_cmd_out_WriteNoSnpFull_fbp{FBP}_ltc{LTC}_l2slice{L2SLICE}'
]
metric_names_emu = [
    '02_PCIe_limited',
    '03_SYSLTC_limited',
    '06_MMU_limited',
    '07_RASTER_limited',
    '08_Rop_limited',
    '10_GCC_limited',
    '11_LTC_limited',
    '12_LST_limited',
    '13_TTU_limited',
    '14_SM_limited',
    '15_FB_limited',
    '16_Launch_pipe_limited',
    'FB_limited',
    'LTC_limited',
    'SYSLTC_limited',
    'FB___bytesPerClk'
]

def load_bucket_metrics(bucket, names, reader):
    results = {}; valid = True 
    for name in names:
        start = int(bucket["start"]); end = int(bucket["end"])
        data = reader.getSingleMetricData(name, timeStart=start, timeEnd=end)
        if data and name in data and len(data[name]):
            results[name] = sum(data[name]) / len(data[name]) 
        else:
            valid = False 
            #raise RuntimeError(f"Metric {name} is missing in time range [{start}, {end}]")
    return results, valid

# Check if a bucket is DRAM limited on N1x
def n1x_is_dram_limited(metrics):
    dram_limited = metrics["DRAM_limited"]
    for limiter in [x for x in metric_names_n1x if "_limited" in x]:
        if metrics[limiter] > dram_limited:
            return False
    return True 

# Check if a bucket is FB limited on Emu
def emu_is_fb_limited(metrics):
    fb_limited = metrics["15_FB_limited"]
    for limiter in [x for x in metric_names_emu if "_limited" in x]:
        if metrics[limiter] > fb_limited:
            return False
    return True 

# Check if a bucket contains single-sector reads/writes on N1x
def n1x_is_chi_single_sector_rw(metrics):
    hshub_rw_bytes = metrics["HSHUB___read_bytes"] + metrics["HSHUB___write_bytes"]
    chi_cmd_count = metrics["ltc_chi_cmd_out_ReadNoSnp_fbp{FBP}_ltc{LTC}_l2slice{L2SLICE}"] + \
        metrics["ltc_chi_cmd_out_WriteNoSnpPartial_fbp{FBP}_ltc{LTC}_l2slice{L2SLICE}"] + \
        metrics["ltc_chi_cmd_out_WriteNoSnpFull_fbp{FBP}_ltc{LTC}_l2slice{L2SLICE}"]
    ratio = hshub_rw_bytes / chi_cmd_count
    return ratio >= 30 and ratio <= 50

# Check if most DRAM traffix is writes 
def n1x_is_most_dram_traffix_writes(metrics):
    return int(metrics['HSHUB___write_bytes']) > int(metrics['HSHUB___read_bytes'])
    
# Find a bucket with given name on Emu
def emu_get_bucket_with_name(name):
    index = 0
    for bucket_emu in reader_emu.getSpanValues("3D0_0"):
        if bucket_emu["type"] != "Buckets" or int(bucket_emu["start"]) < frame_time_emu[0]:
            continue 
        if bucket_emu["name"] == name:
            return bucket_emu, index
        index += 1
    print(f"Failed to find emu bucket with name '{name}'")
    return None, None

# Find frames with the same index on N1x and Emu
if frame_time_n1x[0] < 0 or frame_time_emu[0] < 0:
    found_aligned = False
    for index_n1x, frame_n1x in enumerate(reader_n1x.getSpanValues("frame_0")):
        for index_emu, frame_emu in enumerate(reader_emu.getSpanValues("frame_0")):
            if frame_n1x["name"].split("_")[1] == frame_emu["name"].split("_")[1]:
                found_aligned = True
            if found_aligned: break 
        if found_aligned: break 
    if not found_aligned:
        raise RuntimeError("Failed to find aligned frame")

    # Print aligned frames attributes
    first_frame_n1x = reader_n1x.getSpanValues("frame_0")[index_n1x]
    first_frame_emu = reader_emu.getSpanValues("frame_0")[index_emu]
    frame_time_n1x = [int(first_frame_n1x["start"]), int(first_frame_n1x["end"])]
    frame_time_emu = [int(first_frame_emu["start"]), int(first_frame_emu["end"])]
    frame_duration_n1x = (frame_time_n1x[1] - frame_time_n1x[0]) / 1_000_000.0
    frame_duration_emu = (frame_time_emu[1] - frame_time_emu[0]) / 1_000_000.0
    print(f"N1x frame index: {index_n1x}");
    print(f" N1x frame time: {frame_duration_n1x:.2f} ms ({frame_duration_n1x / frame_duration_emu * 100:.2f}% of Emu)")
    print(f"        N1x FPS: {1000.0 / frame_duration_n1x:.2f} ({((1000.0 / frame_duration_n1x) / (1000.0 / frame_duration_emu))* 100:.2f}% of Emu)")
    print(f"Emu frame index: {index_emu}")
    print(f" Emu frame time: {frame_duration_emu:.2f} ms")
    print(f"        Emu FPS: {1000.0 / frame_duration_emu:.2f}")

if not set(metric_names_n1x).issubset(reader_n1x.getMetricNames()):
    raise RuntimeError(f"Missing metric data on N1x: {list(set(metric_names_n1x) - set(reader_n1x.getMetricNames()))}")
if not set(metric_names_emu).issubset(reader_emu.getMetricNames()):
    raise RuntimeError(f"Missing metric data on Emu: {list(set(metric_names_emu) - set(reader_emu.getMetricNames()))}")

# Total N1x slowdown time caused by CHI
n1x_bucket_count = 0
n1x_chi_limited_bucket_count = 0
n1x_chi_limited_slowdown = 0
n1x_frame_slowdown = 0
for bucket_n1x in reader_n1x.getSpanValues("3D0_0"):
    # Ignore buckets out of bound
    if  bucket_n1x["type"] != "Buckets"  \
        or (int(bucket_n1x["start"]) < frame_time_n1x[0]) \
        or (int(bucket_n1x["end"]) > frame_time_n1x[1]):
        continue 
    
    # Find emu buckets with the same name
    bucket_emu, index_emu = emu_get_bucket_with_name(bucket_n1x["name"])
    if bucket_emu is None or index_emu is None:
        print(f"Failed to find emu bucket with name '{bucket_n1x['name']}'")
        continue 

    # Ignore buckets with missing metrics 
    metrics_n1x, valid_n1x = load_bucket_metrics(bucket_n1x, metric_names_n1x, reader_n1x) 
    metrics_emu, valid_emu = load_bucket_metrics(bucket_emu, metric_names_emu, reader_emu)  
    if not (valid_n1x and valid_emu):
        continue 

    duration_n1x = int(bucket_n1x["end"]) - int(bucket_n1x["start"])
    duration_emu = int(bucket_emu["end"]) - int(bucket_emu["start"])
    #dram_bw_n1x = float(metrics_n1x["HSHUB___DRAM_GB_per_s"])
    #fb_bw_emu = emu_get_fb_bw(metrics_emu)

    # Find slow N1x bucket limited by CHI
    if duration_n1x > duration_emu \
       and n1x_is_dram_limited(metrics_n1x) \
       and (n1x_is_chi_single_sector_rw(metrics_n1x) or n1x_is_most_dram_traffix_writes(metrics_n1x)):
        n1x_chi_limited_bucket_count += 1
        n1x_chi_limited_slowdown += (duration_n1x - duration_emu)
    
    if duration_n1x > duration_emu:
        n1x_frame_slowdown += (duration_n1x - duration_emu)
    n1x_bucket_count += 1

# How much of the additional frame time was caused by CHI limitation on N1x 
print( "N1x CHI limiter (single sector r/w):")
print(f"    - Found in {n1x_chi_limited_bucket_count} out of {n1x_bucket_count} buckets")
print(f"    - Generated {n1x_chi_limited_slowdown / 1_000_000.0:.2f} out of {n1x_frame_slowdown / 1_000_000.0:.2f} ms slowdown ({1.0 * n1x_chi_limited_slowdown / n1x_frame_slowdown * 100:.2f}%)")