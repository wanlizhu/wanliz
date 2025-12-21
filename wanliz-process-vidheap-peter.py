#!/usr/bin/env python3
"""
Script to process vidHeapControl calls from rmlog file.
Parses and analyzes memory allocation operations.
"""

import re
import json
from dataclasses import dataclass, asdict
from typing import Optional, List, Dict
import sys


# NVOS32 Memory Type Definitions
NVOS32_TYPE = {
    0: "IMAGE",
    1: "DEPTH",
    2: "TEXTURE",
    3: "VIDEO",
    4: "FONT",
    5: "CURSOR",
    6: "DMA",
    7: "INSTANCE",
    8: "PRIMARY",
    9: "ZCULL",
    10: "UNUSED",
    11: "SHADER_PROGRAM",
    12: "OWNER_RM",
    13: "NOTIFIER",
    14: "RESERVED",
    15: "PMA",
    16: "STENCIL",
    17: "SYNCPOINT",
}

# NVOS32 Allocation Flags
NVOS32_ALLOC_FLAGS = {
    0x00000001: "IGNORE_BANK_PLACEMENT",
    0x00000002: "FORCE_MEM_GROWS_UP",
    0x00000004: "FORCE_MEM_GROWS_DOWN",
    0x00000008: "FORCE_ALIGN_HOST_PAGE",
    0x00000010: "FIXED_ADDRESS_ALLOCATE",
    0x00000020: "BANK_HINT",
    0x00000040: "BANK_FORCE",
    0x00000080: "ALIGNMENT_HINT",
    0x00000100: "ALIGNMENT_FORCE",
    0x00000200: "BANK_GROW_DOWN",
    0x00000400: "LAZY",
    0x00000800: "FORCE_REVERSE_ALLOC",
    0x00001000: "NO_SCANOUT",
    0x00002000: "PITCH_FORCE",
    0x00004000: "MEMORY_HANDLE_PROVIDED",
    0x00008000: "MAP_NOT_REQUIRED",
    0x00010000: "PERSISTENT_VIDMEM",
    0x00020000: "USE_BEGIN_END",
    0x00040000: "TURBO_CIPHER_ENCRYPTED",
    0x00080000: "VIRTUAL",
    0x00100000: "FORCE_INTERNAL_INDEX",
    0x00200000: "ZCULL_COVG_SPECIFIED",
    0x00400000: "EXTERNALLY_MANAGED",
    0x00800000: "FORCE_DEDICATED_PDE",
    0x01000000: "PROTECTED",
    0x02000000: "KERNEL_MAPPING_MAP/MAXIMIZE_ADDRESS_SPACE",
    0x04000000: "SPARSE/USER_READ_ONLY",
    0x08000000: "DEVICE_READ_ONLY",
    0x10000000: "SKIP_RESOURCE_ALLOC",
    0x20000000: "PREFER_PTES_IN_SYSMEMORY",
    0x40000000: "SKIP_ALIGN_PAD/WPR1",
    0x80000000: "ZCULL_DONT_ALLOCATE_SHARED_1X/WPR2",
}


def extract_bitfield(value: int, high: int, low: int) -> int:
    """Extract a bitfield from a value given high:low bit positions"""
    mask = (1 << (high - low + 1)) - 1
    return (value >> low) & mask


def decode_attr(attr_val: int) -> Dict[str, str]:
    """Decode NVOS32_ATTR bitfield"""
    result = {}
    
    # DEPTH [2:0]
    depth = extract_bitfield(attr_val, 2, 0)
    depth_names = {0: "UNKNOWN", 1: "8", 2: "16", 3: "24", 4: "32", 5: "64", 6: "128"}
    result["depth"] = depth_names.get(depth, str(depth))
    
    # COMPR_COVG [3:3]
    compr_covg = extract_bitfield(attr_val, 3, 3)
    result["compr_covg"] = "PROVIDED" if compr_covg else "DEFAULT"
    
    # AA_SAMPLES [7:4]
    aa = extract_bitfield(attr_val, 7, 4)
    aa_names = {0: "1", 1: "2", 2: "4", 3: "4_ROTATED", 4: "6", 5: "8", 6: "16",
                7: "4_VIRTUAL_8", 8: "4_VIRTUAL_16", 9: "8_VIRTUAL_16", 10: "8_VIRTUAL_32"}
    result["aa_samples"] = aa_names.get(aa, str(aa))
    
    # GPU_CACHE_SNOOPABLE [9:8]
    snoop = extract_bitfield(attr_val, 9, 8)
    snoop_names = {0: "MAPPING", 1: "OFF", 2: "ON", 3: "INVALID"}
    result["gpu_cache_snoop"] = snoop_names.get(snoop, str(snoop))
    
    # ZCULL [11:10]
    zcull = extract_bitfield(attr_val, 11, 10)
    zcull_names = {0: "NONE", 1: "REQUIRED", 2: "ANY", 3: "SHARED"}
    result["zcull"] = zcull_names.get(zcull, str(zcull))
    
    # COMPR [13:12]
    compr = extract_bitfield(attr_val, 13, 12)
    compr_names = {0: "NONE", 1: "REQUIRED", 2: "ANY", 3: "DISABLE_PLC_ANY"}
    result["compr"] = compr_names.get(compr, str(compr))
    
    # ALLOCATE_FROM_RESERVED_HEAP [14:14]
    reserved_heap = extract_bitfield(attr_val, 14, 14)
    result["reserved_heap"] = "YES" if reserved_heap else "NO"
    
    # FORMAT [17:16]
    fmt = extract_bitfield(attr_val, 17, 16)
    fmt_names = {0: "PITCH", 1: "SWIZZLED", 2: "BLOCK_LINEAR"}
    result["format"] = fmt_names.get(fmt, str(fmt))
    
    # Z_TYPE [18:18]
    z_type = extract_bitfield(attr_val, 18, 18)
    result["z_type"] = "FLOAT" if z_type else "FIXED"
    
    # ZS_PACKING [21:19]
    zs = extract_bitfield(attr_val, 21, 19)
    zs_names = {0: "Z24S8/S8", 1: "S8Z24", 2: "Z32", 3: "Z24X8", 4: "X8Z24", 
                5: "Z32_X24S8", 6: "X8Z24_X24S8", 7: "Z16"}
    result["zs_packing"] = zs_names.get(zs, str(zs))
    
    # PAGE_SIZE [24:23]
    page = extract_bitfield(attr_val, 24, 23)
    page_names = {0: "DEFAULT", 1: "4KB", 2: "BIG", 3: "HUGE"}
    result["page_size"] = page_names.get(page, str(page))
    
    # LOCATION [26:25]
    loc = extract_bitfield(attr_val, 26, 25)
    loc_names = {0: "VIDMEM", 1: "PCI", 3: "ANY"}
    result["location"] = loc_names.get(loc, str(loc))
    
    # PHYSICALITY [28:27]
    phys = extract_bitfield(attr_val, 28, 27)
    phys_names = {0: "DEFAULT", 1: "NONCONTIGUOUS", 2: "CONTIGUOUS", 3: "ALLOW_NONCONTIGUOUS"}
    result["physicality"] = phys_names.get(phys, str(phys))
    
    # COHERENCY [31:29]
    coh = extract_bitfield(attr_val, 31, 29)
    coh_names = {0: "UNCACHED", 1: "CACHED", 2: "WRITE_COMBINE", 3: "WRITE_THROUGH",
                 4: "WRITE_PROTECT", 5: "WRITE_BACK"}
    result["coherency"] = coh_names.get(coh, str(coh))
    
    return result


def decode_attr2(attr2_val: int) -> Dict[str, str]:
    """Decode NVOS32_ATTR2 bitfield"""
    result = {}
    
    # ZBC [1:0]
    zbc = extract_bitfield(attr2_val, 1, 0)
    zbc_names = {0: "DEFAULT", 1: "PREFER_NO_ZBC", 2: "PREFER_ZBC", 3: "REQUIRE_ONLY_ZBC"}
    result["zbc"] = zbc_names.get(zbc, str(zbc))
    
    # GPU_CACHEABLE [3:2]
    cacheable = extract_bitfield(attr2_val, 3, 2)
    cache_names = {0: "DEFAULT", 1: "YES", 2: "NO", 3: "INVALID"}
    result["gpu_cacheable"] = cache_names.get(cacheable, str(cacheable))
    
    # P2P_GPU_CACHEABLE [5:4]
    p2p = extract_bitfield(attr2_val, 5, 4)
    result["p2p_gpu_cacheable"] = cache_names.get(p2p, str(p2p))
    
    # 32BIT_POINTER [6:6]
    ptr32 = extract_bitfield(attr2_val, 6, 6)
    result["32bit_pointer"] = "ENABLE" if ptr32 else "DISABLE"
    
    # FIXED_NUMA_NODE_ID [7:7]
    numa = extract_bitfield(attr2_val, 7, 7)
    result["fixed_numa"] = "YES" if numa else "NO"
    
    # SMMU_ON_GPU [9:8]
    smmu = extract_bitfield(attr2_val, 9, 8)
    smmu_names = {0: "DEFAULT", 1: "DISABLE", 2: "ENABLE"}
    result["smmu_on_gpu"] = smmu_names.get(smmu, str(smmu))
    
    # USE_SCANOUT_CARVEOUT [10:10]
    scanout = extract_bitfield(attr2_val, 10, 10)
    result["scanout_carveout"] = "TRUE" if scanout else "FALSE"
    
    # ALLOC_COMPCACHELINE_ALIGN [11:11]
    align = extract_bitfield(attr2_val, 11, 11)
    result["compcacheline_align"] = "ON" if align else "OFF"
    
    # PRIORITY [13:12]
    priority = extract_bitfield(attr2_val, 13, 12)
    priority_names = {0: "DEFAULT", 1: "HIGH", 2: "LOW"}
    result["priority"] = priority_names.get(priority, str(priority))
    
    # INTERNAL [14:14]
    internal = extract_bitfield(attr2_val, 14, 14)
    result["internal"] = "YES" if internal else "NO"
    
    # PREFER_2C [15:15]
    prefer2c = extract_bitfield(attr2_val, 15, 15)
    result["prefer_2c"] = "YES" if prefer2c else "NO"
    
    # NISO_DISPLAY [16:16]
    display = extract_bitfield(attr2_val, 16, 16)
    result["niso_display"] = "YES" if display else "NO"
    
    # ZBC_SKIP_ZBCREFCOUNT [17:17]
    skip_zbc = extract_bitfield(attr2_val, 17, 17)
    result["zbc_skip_refcount"] = "YES" if skip_zbc else "NO"
    
    # ISO [18:18]
    iso = extract_bitfield(attr2_val, 18, 18)
    result["iso"] = "YES" if iso else "NO"
    
    # PAGE_OFFLINING [19:19]
    offlining = extract_bitfield(attr2_val, 19, 19)
    result["page_offlining"] = "OFF" if offlining else "ON"
    
    # PAGE_SIZE_HUGE [21:20]
    huge = extract_bitfield(attr2_val, 21, 20)
    huge_names = {0: "DEFAULT", 1: "2MB", 2: "512MB", 3: "256GB"}
    result["page_size_huge"] = huge_names.get(huge, str(huge))
    
    # PROTECTION_USER [22:22]
    user_prot = extract_bitfield(attr2_val, 22, 22)
    result["protection_user"] = "READ_ONLY" if user_prot else "READ_WRITE"
    
    # PROTECTION_DEVICE [23:23]
    dev_prot = extract_bitfield(attr2_val, 23, 23)
    result["protection_device"] = "READ_ONLY" if dev_prot else "READ_WRITE"
    
    # MEMORY_PROTECTION [26:25]
    mem_prot = extract_bitfield(attr2_val, 26, 25)
    mem_prot_names = {0: "DEFAULT", 1: "PROTECTED", 2: "UNPROTECTED"}
    result["memory_protection"] = mem_prot_names.get(mem_prot, str(mem_prot))
    
    # ALLOCATE_FROM_SUBHEAP [27:27]
    subheap = extract_bitfield(attr2_val, 27, 27)
    result["allocate_from_subheap"] = "YES" if subheap else "NO"
    
    # ENABLE_LOCALIZED_MEMORY [30:29]
    localized = extract_bitfield(attr2_val, 30, 29)
    localized_names = {0: "DEFAULT", 1: "UGPU0", 2: "UGPU1"}
    result["localized_memory"] = localized_names.get(localized, str(localized))
    
    # REGISTER_MEMDESC_TO_PHYS_RM [31:31]
    register = extract_bitfield(attr2_val, 31, 31)
    result["register_memdesc"] = "TRUE" if register else "FALSE"
    
    return result


def decode_flags(flags_val: int) -> List[str]:
    """Decode allocation flags bitmask"""
    active_flags = []
    for flag_bit, flag_name in NVOS32_ALLOC_FLAGS.items():
        if flags_val & flag_bit:
            active_flags.append(flag_name)
    return active_flags


def decode_type(type_val: int) -> str:
    """Decode memory type"""
    return NVOS32_TYPE.get(type_val, f"UNKNOWN({type_val})")


def decode_nvos46_flags(flags_val: int) -> Dict[str, str]:
    """Decode NVOS46_FLAGS bitfield for mapMemoryDma"""
    result = {}
    
    # ACCESS [1:0]
    access = extract_bitfield(flags_val, 1, 0)
    access_names = {0: "READ_WRITE", 1: "READ_ONLY", 2: "WRITE_ONLY"}
    result["access"] = access_names.get(access, str(access))
    
    # 32BIT_POINTER [2:2]
    ptr32 = extract_bitfield(flags_val, 2, 2)
    result["32bit_pointer"] = "ENABLE" if ptr32 else "DISABLE"
    
    # PAGE_KIND [3:3]
    page_kind = extract_bitfield(flags_val, 3, 3)
    result["page_kind"] = "VIRTUAL" if page_kind else "PHYSICAL"
    
    # CACHE_SNOOP [4:4]
    cache_snoop = extract_bitfield(flags_val, 4, 4)
    result["cache_snoop"] = "ENABLE" if cache_snoop else "DISABLE"
    
    # KERNEL_MAPPING [5:5]
    kernel_map = extract_bitfield(flags_val, 5, 5)
    result["kernel_mapping"] = "ENABLE" if kernel_map else "NONE"
    
    # SHADER_ACCESS [7:6]
    shader = extract_bitfield(flags_val, 7, 6)
    shader_names = {0: "DEFAULT", 1: "READ_ONLY", 2: "WRITE_ONLY", 3: "READ_WRITE"}
    result["shader_access"] = shader_names.get(shader, str(shader))
    
    # PAGE_SIZE [11:8]
    page_size = extract_bitfield(flags_val, 11, 8)
    page_size_names = {0: "DEFAULT", 1: "4KB", 2: "BIG", 3: "BOTH", 4: "HUGE", 5: "512M"}
    result["page_size"] = page_size_names.get(page_size, str(page_size))
    
    # SYSTEM_L3_ALLOC [13:13]
    l3_alloc = extract_bitfield(flags_val, 13, 13)
    result["system_l3_alloc"] = "ENABLE_HINT" if l3_alloc else "DEFAULT"
    
    # DMA_OFFSET_GROWS [14:14]
    offset_grows = extract_bitfield(flags_val, 14, 14)
    result["dma_offset_grows"] = "DOWN" if offset_grows else "UP"
    
    # DMA_OFFSET_FIXED [15:15]
    offset_fixed = extract_bitfield(flags_val, 15, 15)
    result["dma_offset_fixed"] = "TRUE" if offset_fixed else "FALSE"
    
    # DISABLE_ENCRYPTION [16:16]
    disable_enc = extract_bitfield(flags_val, 16, 16)
    result["disable_encryption"] = "TRUE" if disable_enc else "FALSE"
    
    # GPU_CACHEABLE [18:17]
    gpu_cache = extract_bitfield(flags_val, 18, 17)
    gpu_cache_names = {0: "DEFAULT", 1: "YES", 2: "NO", 3: "INVALID"}
    result["gpu_cacheable"] = gpu_cache_names.get(gpu_cache, str(gpu_cache))
    
    # PAGE_KIND_OVERRIDE [19:19]
    kind_override = extract_bitfield(flags_val, 19, 19)
    result["page_kind_override"] = "YES" if kind_override else "NO"
    
    # P2P_ENABLE [21:20]
    p2p = extract_bitfield(flags_val, 21, 20)
    p2p_names = {0: "NO", 1: "YES/SLI", 2: "NOSLI", 3: "LOOPBACK"}
    result["p2p_enable"] = p2p_names.get(p2p, str(p2p))
    
    # P2P_SUBDEV_ID_SRC [24:22]
    subdev_src = extract_bitfield(flags_val, 24, 22)
    if subdev_src:
        result["p2p_subdev_src"] = str(subdev_src)
    
    # P2P_SUBDEV_ID_TGT [27:25]
    subdev_tgt = extract_bitfield(flags_val, 27, 25)
    if subdev_tgt:
        result["p2p_subdev_tgt"] = str(subdev_tgt)
    
    # TLB_LOCK [28:28]
    tlb_lock = extract_bitfield(flags_val, 28, 28)
    result["tlb_lock"] = "ENABLE" if tlb_lock else "DISABLE"
    
    # DMA_UNICAST_REUSE_ALLOC [29:29]
    reuse = extract_bitfield(flags_val, 29, 29)
    result["dma_unicast_reuse"] = "TRUE" if reuse else "FALSE"
    
    # ENABLE_FORCE_COMPRESSED_MAP [30:30]
    force_compressed = extract_bitfield(flags_val, 30, 30)
    result["force_compressed"] = "TRUE" if force_compressed else "FALSE"
    
    # DEFER_TLB_INVALIDATION [31:31]
    defer_tlb = extract_bitfield(flags_val, 31, 31)
    result["defer_tlb_inval"] = "TRUE" if defer_tlb else "FALSE"
    
    return result


def decode_nvos46_flags2(flags2_val: int) -> Dict[str, str]:
    """Decode NVOS46_FLAGS2 bitfield for mapMemoryDma"""
    result = {}
    
    # GPU_CACHE_SNOOP [1:0]
    snoop = extract_bitfield(flags2_val, 1, 0)
    snoop_names = {0: "DEFAULT", 1: "ENABLE", 2: "DISABLE"}
    result["gpu_cache_snoop"] = snoop_names.get(snoop, str(snoop))
    
    return result


@dataclass
class AllocSize:
    """Represents the AllocSize structure from vidHeapControl"""
    owner: str
    hMemory: str
    type: str
    flags: str
    attr: str
    format: str
    comprCovg: str
    zcullCovg: str
    width: str
    height: str
    size: str
    alignment: str
    offset: str
    limit: str
    address: str
    rangeBegin: str
    rangeEnd: str
    attr2: str
    ctagOffset: str
    numaNode: str


@dataclass
class VidHeapControlCall:
    """Represents a complete vidHeapControl call"""
    line_number: int
    hRoot: str
    hObjectParent: str
    function: str
    hVASpace: str
    ivcHeapNumber: str
    status_before: str
    total: str
    free: str
    alloc_size_before: AllocSize
    alloc_ptr: Optional[str]
    bl_ptr: Optional[str]
    status_after: str
    duration_ns: int
    alloc_size_after: AllocSize


@dataclass
class MapMemoryDmaCall:
    """Represents a mapMemoryDma2 call"""
    line_number: int
    hClient: str
    hDevice: str
    hDma: str
    hMemory: str
    offset: str
    length: str
    flags: str
    flags2: str
    kindOverride: str
    dmaOffset_before: str
    status: str
    duration_ns: int
    dmaOffset_after: str


@dataclass
class DupObjectCall:
    """Represents a dupObject2 call that creates an alias"""
    line_number: int
    hClient: str
    hParent: str
    hClientSrc: str
    hObjectSrc: str
    hObjectDest: str
    flags: str
    status: str
    duration_ns: int


def parse_alloc_size(alloc_str: str) -> AllocSize:
    """Parse AllocSize structure from string"""
    # Remove 'AllocSize={' and trailing '}'
    alloc_str = alloc_str.strip()
    if alloc_str.startswith('AllocSize={'):
        alloc_str = alloc_str[11:]
    if alloc_str.endswith('}'):
        alloc_str = alloc_str[:-1]
    
    # Parse key=value pairs
    params = {}
    # Use regex to handle complex values including (nil)
    pattern = r'(\w+)=((?:\([^)]+\)|0x[0-9a-f]+|0|-?\d+))'
    matches = re.finditer(pattern, alloc_str)
    
    for match in matches:
        key, value = match.groups()
        params[key] = value
    
    return AllocSize(
        owner=params.get('owner', '0x0'),
        hMemory=params.get('hMemory', '0x0'),
        type=params.get('type', '0x0'),
        flags=params.get('flags', '0x0'),
        attr=params.get('attr', '0x0'),
        format=params.get('format', '0x0'),
        comprCovg=params.get('comprCovg', '0x0'),
        zcullCovg=params.get('zcullCovg', '0x0'),
        width=params.get('width', '0x0'),
        height=params.get('height', '0x0'),
        size=params.get('size', '0x0'),
        alignment=params.get('alignment', '0x0'),
        offset=params.get('offset', '0x0'),
        limit=params.get('limit', '0x0'),
        address=params.get('address', '(nil)'),
        rangeBegin=params.get('rangeBegin', '0x0'),
        rangeEnd=params.get('rangeEnd', '0x0'),
        attr2=params.get('attr2', '0x0'),
        ctagOffset=params.get('ctagOffset', '0x0'),
        numaNode=params.get('numaNode', '0')
    )


def parse_vidheap_control_line(line: str, line_number: int) -> Optional[VidHeapControlCall]:
    """Parse a single vidHeapControl line"""
    if 'vidHeapControl' not in line:
        return None
    
    try:
        # Split into before -> after
        parts = line.split(' -> ')
        if len(parts) != 2:
            return None
        
        before_part = parts[0]
        after_part = parts[1]
        
        # Extract parameters from before part
        # Pattern: RM: vidHeapControl(vidHeapControlParms={...}, alloc=..., bl=...)
        before_match = re.search(r'vidHeapControl\(vidHeapControlParms=\{([^}]+(?:\{[^}]+\})?[^}]*)\}, alloc=([^,]+), bl=([^)]+)\)', before_part)
        if not before_match:
            return None
        
        params_str = before_match.group(1)
        alloc_ptr = before_match.group(2)
        bl_ptr = before_match.group(3)
        
        # Extract main parameters
        param_pattern = r'(\w+)=((?:0x[0-9a-f]+|0x0|\d+|AllocSize=\{[^}]+\}))'
        main_params = {}
        
        # Find AllocSize first (it's a nested structure)
        alloc_size_match = re.search(r'AllocSize=\{([^}]+)\}', params_str)
        if alloc_size_match:
            alloc_size_str = alloc_size_match.group(0)
            alloc_size_before = parse_alloc_size(alloc_size_str)
            # Remove AllocSize from params_str to parse other parameters
            params_without_alloc = params_str.replace(alloc_size_str, '')
        else:
            return None
        
        # Parse other parameters
        for match in re.finditer(r'(\w+)=(0x[0-9a-f]+|0x0|\d+)', params_without_alloc):
            key, value = match.groups()
            main_params[key] = value
        
        # Extract after part
        # Pattern: status=..., duration=...ns, vidHeapControlParms={...}
        status_match = re.search(r'status=(0x[0-9a-f]+)', after_part)
        duration_match = re.search(r'duration=(\d+)ns', after_part)
        after_params_match = re.search(r'vidHeapControlParms=\{[^}]*AllocSize=\{([^}]+)\}', after_part)
        
        if not (status_match and duration_match):
            return None
        
        status_after = status_match.group(1)
        duration_ns = int(duration_match.group(1))
        
        # Parse after AllocSize
        if after_params_match:
            # Find the full AllocSize in after part
            after_alloc_match = re.search(r'AllocSize=\{([^}]+)\}', after_part)
            if after_alloc_match:
                alloc_size_after = parse_alloc_size(after_alloc_match.group(0))
            else:
                alloc_size_after = alloc_size_before
        else:
            alloc_size_after = alloc_size_before
        
        return VidHeapControlCall(
            line_number=line_number,
            hRoot=main_params.get('hRoot', '0x0'),
            hObjectParent=main_params.get('hObjectParent', '0x0'),
            function=main_params.get('function', '0x0'),
            hVASpace=main_params.get('hVASpace', '0x0'),
            ivcHeapNumber=main_params.get('ivcHeapNumber', '0x0'),
            status_before=main_params.get('status', '0x0'),
            total=main_params.get('total', '0x0'),
            free=main_params.get('free', '0x0'),
            alloc_size_before=alloc_size_before,
            alloc_ptr=alloc_ptr if alloc_ptr != '(nil)' else None,
            bl_ptr=bl_ptr if bl_ptr != '(nil)' else None,
            status_after=status_after,
            duration_ns=duration_ns,
            alloc_size_after=alloc_size_after
        )
    
    except Exception as e:
        print(f"Error parsing line {line_number}: {e}", file=sys.stderr)
        return None


def parse_mapmemory_dma_line(line: str, line_number: int) -> Optional[MapMemoryDmaCall]:
    """Parse a single mapMemoryDma2 line"""
    if 'mapMemoryDma' not in line:
        return None
    
    try:
        # Split into before -> after
        parts = line.split(' -> ')
        if len(parts) != 2:
            return None
        
        before_part = parts[0]
        after_part = parts[1]
        
        # Extract parameters from before part
        # Pattern: RM: mapMemoryDma2(parms={...})
        before_match = re.search(r'mapMemoryDma\d?\(parms=\{([^}]+)\}\)', before_part)
        if not before_match:
            return None
        
        params_str = before_match.group(1)
        
        # Parse parameters
        params = {}
        param_pattern = r'(\w+)=(0x[0-9a-f]+|0x0|\d+)'
        for match in re.finditer(param_pattern, params_str):
            key, value = match.groups()
            params[key] = value
        
        # Extract after part
        status_match = re.search(r'status=(0x[0-9a-f]+)', after_part)
        duration_match = re.search(r'duration=(\d+)ns', after_part)
        after_params_match = re.search(r'parms=\{([^}]+)\}', after_part)
        
        if not (status_match and duration_match and after_params_match):
            return None
        
        status = status_match.group(1)
        duration_ns = int(duration_match.group(1))
        
        # Parse after parameters to get updated dmaOffset
        after_params_str = after_params_match.group(1)
        after_params = {}
        for match in re.finditer(param_pattern, after_params_str):
            key, value = match.groups()
            after_params[key] = value
        
        return MapMemoryDmaCall(
            line_number=line_number,
            hClient=params.get('hClient', '0x0'),
            hDevice=params.get('hDevice', '0x0'),
            hDma=params.get('hDma', '0x0'),
            hMemory=params.get('hMemory', '0x0'),
            offset=params.get('offset', '0x0'),
            length=params.get('length', '0x0'),
            flags=params.get('flags', '0x0'),
            flags2=params.get('flags2', '0x0'),
            kindOverride=params.get('kindOverride', '0x0'),
            dmaOffset_before=params.get('dmaOffset', '0x0'),
            status=status,
            duration_ns=duration_ns,
            dmaOffset_after=after_params.get('dmaOffset', params.get('dmaOffset', '0x0'))
        )
    
    except Exception as e:
        print(f"Error parsing mapMemoryDma line {line_number}: {e}", file=sys.stderr)
        return None


def parse_dupobject_line(line: str, line_number: int) -> Optional[DupObjectCall]:
    """Parse a single dupObject2 line"""
    if 'dupObject' not in line:
        return None
    
    try:
        # Split into before -> after
        parts = line.split(' -> ')
        if len(parts) != 2:
            return None
        
        before_part = parts[0]
        after_part = parts[1]
        
        # Extract parameters from before part
        # Pattern: RM: dupObject2(hClient=..., hParent=..., hObjectDest=..., hClientSrc=..., hObjectSrc=..., flags=...)
        params = {}
        param_pattern = r'(\w+)=(0x[0-9a-f]+|0x0|\d+|\(nil\))'
        for match in re.finditer(param_pattern, before_part):
            key, value = match.groups()
            params[key] = value
        
        # Extract after part
        status_match = re.search(r'status=(0x[0-9a-f]+)', after_part)
        duration_match = re.search(r'duration=(\d+)ns', after_part)
        dest_match = re.search(r'hObjectDest=(0x[0-9a-f]+)', after_part)
        
        if not (status_match and duration_match and dest_match):
            return None
        
        status = status_match.group(1)
        duration_ns = int(duration_match.group(1))
        hObjectDest = dest_match.group(1)
        
        return DupObjectCall(
            line_number=line_number,
            hClient=params.get('hClient', '0x0'),
            hParent=params.get('hParent', '0x0'),
            hClientSrc=params.get('hClientSrc', '0x0'),
            hObjectSrc=params.get('hObjectSrc', '0x0'),
            hObjectDest=hObjectDest,
            flags=params.get('flags', '0x0'),
            status=status,
            duration_ns=duration_ns
        )
    
    except Exception as e:
        print(f"Error parsing dupObject line {line_number}: {e}", file=sys.stderr)
        return None


def parse_hex_or_int(value_str: str) -> int:
    """Parse a hex or decimal string to integer"""
    try:
        if value_str.startswith('0x'):
            return int(value_str, 16)
        else:
            return int(value_str)
    except:
        return 0


def format_size(size_str: str) -> str:
    """Format size in human-readable format"""
    try:
        if size_str.startswith('0x'):
            size = int(size_str, 16)
        else:
            size = int(size_str)
        
        if size >= 1024*1024*1024:
            return f"{size/(1024*1024*1024):.2f} GB ({size_str})"
        elif size >= 1024*1024:
            return f"{size/(1024*1024):.2f} MB ({size_str})"
        elif size >= 1024:
            return f"{size/1024:.2f} KB ({size_str})"
        else:
            return f"{size} B ({size_str})"
    except:
        return size_str


def build_alias_map(dupobject_calls: List[DupObjectCall]) -> Dict[str, str]:
    """Build a map from alias handles (hObjectDest) to source handles (hObjectSrc)"""
    alias_map = {}
    for call in dupobject_calls:
        if call.status == '0x0':  # Only track successful dupObject calls
            alias_map[call.hObjectDest] = call.hObjectSrc
    return alias_map


def resolve_alias(handle: str, alias_map: Dict[str, str]) -> str:
    """Resolve a handle through the alias chain to get the original handle"""
    seen = set()
    current = handle
    while current in alias_map:
        if current in seen:
            # Circular reference, break
            break
        seen.add(current)
        current = alias_map[current]
    return current


def build_allocation_map(vidheap_calls: List[VidHeapControlCall], alias_map: Dict[str, str]) -> Dict[str, VidHeapControlCall]:
    """Build a map from hMemory handles (including aliases) to their allocation calls"""
    alloc_map = {}
    
    # First, build map for original allocations
    for call in vidheap_calls:
        h_memory = call.alloc_size_after.hMemory
        if h_memory and h_memory != '0x0':
            alloc_map[h_memory] = call
    
    # Then, add entries for all aliases
    for alias_handle, source_handle in alias_map.items():
        # Resolve the source handle through any alias chain
        original_handle = resolve_alias(source_handle, alias_map)
        if original_handle in alloc_map:
            alloc_map[alias_handle] = alloc_map[original_handle]
    
    return alloc_map


def find_related_allocations(mapmemory_call: MapMemoryDmaCall, alloc_map: Dict[str, VidHeapControlCall], alias_map: Dict[str, str] = None) -> tuple[Optional[VidHeapControlCall], Optional[VidHeapControlCall], Optional[str], Optional[str]]:
    """Find related allocations for a mapMemoryDma call
    
    Returns:
        (alloc_from_hMemory, alloc_from_hDma, resolved_hMemory, resolved_hDma)
        resolved handles show the original handle if found via alias, None if direct match
    """
    if alias_map is None:
        alias_map = {}
    
    alloc_from_hmemory = alloc_map.get(mapmemory_call.hMemory)
    alloc_from_hdma = alloc_map.get(mapmemory_call.hDma)
    
    # Check if handles were resolved via aliases
    resolved_hmemory = None
    resolved_hdma = None
    
    if mapmemory_call.hMemory in alias_map:
        resolved_hmemory = resolve_alias(mapmemory_call.hMemory, alias_map)
    
    if mapmemory_call.hDma in alias_map:
        resolved_hdma = resolve_alias(mapmemory_call.hDma, alias_map)
    
    # Avoid returning the same allocation twice
    if alloc_from_hmemory and alloc_from_hdma and alloc_from_hmemory == alloc_from_hdma:
        return alloc_from_hmemory, None, resolved_hmemory, None
    
    return alloc_from_hmemory, alloc_from_hdma, resolved_hmemory, resolved_hdma


def process_rmlog(filename: str) -> tuple[List[VidHeapControlCall], List[MapMemoryDmaCall], List[DupObjectCall]]:
    """Process the rmlog file and extract all vidHeapControl, mapMemoryDma, and dupObject calls"""
    vidheap_calls = []
    mapmemory_calls = []
    dupobject_calls = []
    
    with open(filename, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.split('#', 1)[0]
            line_stripped = line.strip()
            
            # Try parsing as vidHeapControl
            vidheap_call = parse_vidheap_control_line(line_stripped, line_num)
            if vidheap_call:
                vidheap_calls.append(vidheap_call)
                continue
            
            # Try parsing as mapMemoryDma
            mapmemory_call = parse_mapmemory_dma_line(line_stripped, line_num)
            if mapmemory_call:
                mapmemory_calls.append(mapmemory_call)
                continue
            
            # Try parsing as dupObject
            dupobject_call = parse_dupobject_line(line_stripped, line_num)
            if dupobject_call:
                dupobject_calls.append(dupobject_call)
    
    return vidheap_calls, mapmemory_calls, dupobject_calls


def print_summary(calls: List[VidHeapControlCall]):
    """Print summary statistics for vidHeapControl calls"""
    print(f"\n{'='*80}")
    print(f"VidHeapControl Summary")
    print(f"{'='*80}")
    print(f"Total calls: {len(calls)}")
    
    # Calculate total allocated size
    total_allocated = 0
    successful_allocs = 0
    failed_allocs = 0
    
    for call in calls:
        if call.status_after == '0x0':
            successful_allocs += 1
            try:
                size_str = call.alloc_size_after.size
                if size_str.startswith('0x'):
                    size = int(size_str, 16)
                else:
                    size = int(size_str)
                total_allocated += size
            except:
                pass
        else:
            failed_allocs += 1
    
    print(f"Successful allocations: {successful_allocs}")
    print(f"Failed allocations: {failed_allocs}")
    print(f"Total memory allocated: {format_size(hex(total_allocated))}")
    
    # Average duration
    avg_duration = sum(call.duration_ns for call in calls) / len(calls) if calls else 0
    print(f"Average duration: {avg_duration:.0f} ns ({avg_duration/1000:.2f} µs)")
    
    # Min/Max duration
    if calls:
        min_duration = min(call.duration_ns for call in calls)
        max_duration = max(call.duration_ns for call in calls)
        print(f"Min duration: {min_duration} ns ({min_duration/1000:.2f} µs)")
        print(f"Max duration: {max_duration} ns ({max_duration/1000:.2f} µs)")


def print_mapmemory_summary(calls: List[MapMemoryDmaCall]):
    """Print summary statistics for mapMemoryDma calls"""
    print(f"\n{'='*80}")
    print(f"MapMemoryDma Summary")
    print(f"{'='*80}")
    print(f"Total calls: {len(calls)}")
    
    # Calculate total mapped size
    total_mapped = 0
    successful_maps = 0
    failed_maps = 0
    
    for call in calls:
        if call.status == '0x0':
            successful_maps += 1
            try:
                length_str = call.length
                if length_str.startswith('0x'):
                    length = int(length_str, 16)
                else:
                    length = int(length_str)
                total_mapped += length
            except:
                pass
        else:
            failed_maps += 1
    
    print(f"Successful mappings: {successful_maps}")
    print(f"Failed mappings: {failed_maps}")
    print(f"Total memory mapped: {format_size(hex(total_mapped))}")
    
    # Average duration
    avg_duration = sum(call.duration_ns for call in calls) / len(calls) if calls else 0
    print(f"Average duration: {avg_duration:.0f} ns ({avg_duration/1000:.2f} µs)")
    
    # Min/Max duration
    if calls:
        min_duration = min(call.duration_ns for call in calls)
        max_duration = max(call.duration_ns for call in calls)
        print(f"Min duration: {min_duration} ns ({min_duration/1000:.2f} µs)")
        print(f"Max duration: {max_duration} ns ({max_duration/1000:.2f} µs)")


def print_interleaved_detailed(vidheap_calls: List[VidHeapControlCall], mapmemory_calls: List[MapMemoryDmaCall], dupobject_calls: List[DupObjectCall], max_calls: int = 10, alloc_map: Dict[str, VidHeapControlCall] = None, alias_map: Dict[str, str] = None, source_file: str = None):
    """Print detailed information for all operations interleaved by line number"""
    print(f"\n{'='*80}")
    if source_file:
        print(f"Detailed Operations from {source_file} (interleaved, showing first {max_calls})")
    else:
        print(f"Detailed Operations (interleaved, showing first {max_calls})")
    print(f"{'='*80}")
    
    if alloc_map is None:
        alloc_map = {}
    if alias_map is None:
        alias_map = {}
    
    # Create a combined list with type tags
    combined = []
    for call in vidheap_calls:
        combined.append(('vidheap', call.line_number, call))
    for call in mapmemory_calls:
        combined.append(('mapmemory', call.line_number, call))
    for call in dupobject_calls:
        combined.append(('dupobject', call.line_number, call))
    
    # Sort by line number
    combined.sort(key=lambda x: x[1])
    
    # Print first N calls
    for i, (call_type, line_num, call) in enumerate(combined[:max_calls], 1):
        if call_type == 'vidheap':
            print(f"\n{'='*80}")
            print(f"║ 📋 VIDHEAPCONTROL Call #{i} (Line {line_num})")
            print(f"{'='*80}")
            print(f"  Function: {call.function}")
            print(f"  hRoot: {call.hRoot}")
            print(f"  hObjectParent: {call.hObjectParent}")
            print(f"  hVASpace: {call.hVASpace}")
            print(f"  Status: {call.status_after}")
            print(f"  Duration: {call.duration_ns} ns ({call.duration_ns/1000:.2f} µs)")
            print(f"  Alloc ptr: {call.alloc_ptr}")
            print(f"  BL ptr: {call.bl_ptr}")
            print()
            
            # Decode before values
            before_type_val = parse_hex_or_int(call.alloc_size_before.type)
            before_type_decoded = decode_type(before_type_val)
            before_flags_val = parse_hex_or_int(call.alloc_size_before.flags)
            before_flags_decoded = decode_flags(before_flags_val)
            before_attr_val = parse_hex_or_int(call.alloc_size_before.attr)
            before_attr_decoded = decode_attr(before_attr_val)
            before_attr2_val = parse_hex_or_int(call.alloc_size_before.attr2)
            before_attr2_decoded = decode_attr2(before_attr2_val)
            
            # Decode after values
            after_type_val = parse_hex_or_int(call.alloc_size_after.type)
            after_type_decoded = decode_type(after_type_val)
            after_flags_val = parse_hex_or_int(call.alloc_size_after.flags)
            after_flags_decoded = decode_flags(after_flags_val)
            after_attr_val = parse_hex_or_int(call.alloc_size_after.attr)
            after_attr_decoded = decode_attr(after_attr_val)
            after_attr2_val = parse_hex_or_int(call.alloc_size_after.attr2)
            after_attr2_decoded = decode_attr2(after_attr2_val)
            
            # Print table header
            print(f"  {'Field':<20} │ {'Before':<35} │ {'After':<35}")
            print(f"  {'─'*20}─┼─{'─'*35}─┼─{'─'*35}")
            
            # Basic fields
            print(f"  {'hMemory':<20} │ {call.alloc_size_before.hMemory:<35} │ {call.alloc_size_after.hMemory:<35}")
            before_type_str = f"{call.alloc_size_before.type} ({before_type_decoded})"
            after_type_str = f"{call.alloc_size_after.type} ({after_type_decoded})"
            print(f"  {'Type':<20} │ {before_type_str:<35} │ {after_type_str:<35}")
            print(f"  {'Size':<20} │ {format_size(call.alloc_size_before.size):<35} │ {format_size(call.alloc_size_after.size):<35}")
            print(f"  {'Alignment':<20} │ {call.alloc_size_before.alignment:<35} │ {call.alloc_size_after.alignment:<35}")
            
            # Flags
            print(f"  {'Flags':<20} │ {call.alloc_size_before.flags:<35} │ {call.alloc_size_after.flags:<35}")
            if before_flags_decoded or after_flags_decoded:
                before_flags_str = ', '.join(before_flags_decoded) if before_flags_decoded else ''
                after_flags_str = ', '.join(after_flags_decoded) if after_flags_decoded else ''
                # Split long flag strings into multiple lines
                if len(before_flags_str) > 33 or len(after_flags_str) > 33:
                    before_parts = [before_flags_str[i:i+33] for i in range(0, len(before_flags_str), 33)] if before_flags_str else ['']
                    after_parts = [after_flags_str[i:i+33] for i in range(0, len(after_flags_str), 33)] if after_flags_str else ['']
                    max_parts = max(len(before_parts), len(after_parts))
                    for idx in range(max_parts):
                        b = before_parts[idx] if idx < len(before_parts) else ''
                        a = after_parts[idx] if idx < len(after_parts) else ''
                        print(f"  {'':<20} │ {b:<35} │ {a:<35}")
                else:
                    print(f"  {'':<20} │ {before_flags_str:<35} │ {after_flags_str:<35}")
            
            # Attr fields
            print(f"  {'Attr':<20} │ {call.alloc_size_before.attr:<35} │ {call.alloc_size_after.attr:<35}")
            # Key attr values in table
            for key in ['location', 'format', 'page_size', 'physicality', 'coherency']:
                before_val = before_attr_decoded.get(key, '')
                after_val = after_attr_decoded.get(key, '')
                print(f"  {'  '+key:<20} │ {before_val:<35} │ {after_val:<35}")
            
            # Attr2 fields
            print(f"  {'Attr2':<20} │ {call.alloc_size_before.attr2:<35} │ {call.alloc_size_after.attr2:<35}")
            # Key attr2 values in table
            for key in ['zbc', 'gpu_cacheable', 'priority', 'memory_protection']:
                before_val = before_attr2_decoded.get(key, '')
                after_val = after_attr2_decoded.get(key, '')
                print(f"  {'  '+key:<20} │ {before_val:<35} │ {after_val:<35}")
            
            # Final fields (only in after)
            print(f"  {'Offset':<20} │ {'':<35} │ {call.alloc_size_after.offset:<35}")
            print(f"  {'Limit':<20} │ {'':<35} │ {call.alloc_size_after.limit:<35}")
            
        elif call_type == 'mapmemory':
            # Show related allocations
            alloc_from_hmemory, alloc_from_hdma, resolved_hmemory, resolved_hdma = find_related_allocations(call, alloc_map, alias_map)
            
            # Highlight if missing allocations
            missing_allocs = not alloc_from_hmemory and not alloc_from_hdma
            print(f"\n{'='*80}")
            if missing_allocs:
                print(f"║ 🔗 MAPMEMORYDMA Call #{i} (Line {line_num}) ⚠️  *** MISSING ALLOCATIONS ***")
            else:
                print(f"║ 🔗 MAPMEMORYDMA Call #{i} (Line {line_num})")
            print(f"{'='*80}")
            
            print(f"  hClient: {call.hClient}")
            print(f"  hDevice: {call.hDevice}")
            print(f"  hDma: {call.hDma}")
            print(f"  hMemory: {call.hMemory}")
            
            if alloc_from_hmemory:
                if resolved_hmemory:
                    print(f"  → Related allocation (via hMemory={call.hMemory} → alias of {resolved_hmemory}):")
                else:
                    print(f"  → Related allocation (via hMemory={call.hMemory}):")
                print(f"     Line: {alloc_from_hmemory.line_number}")
                print(f"     Allocated size: {format_size(alloc_from_hmemory.alloc_size_after.size)}")
                type_val = parse_hex_or_int(alloc_from_hmemory.alloc_size_after.type)
                print(f"     Type: {decode_type(type_val)}")
                attr_val = parse_hex_or_int(alloc_from_hmemory.alloc_size_after.attr)
                attr_decoded = decode_attr(attr_val)
                print(f"     Location: {attr_decoded.get('location', 'UNKNOWN')}")
            else:
                print(f"  ⚠️  No allocation found for hMemory={call.hMemory}")
            
            if alloc_from_hdma:
                if resolved_hdma:
                    print(f"  → Related allocation (via hDma={call.hDma} → alias of {resolved_hdma}):")
                else:
                    print(f"  → Related allocation (via hDma={call.hDma}):")
                print(f"     Line: {alloc_from_hdma.line_number}")
                print(f"     Allocated size: {format_size(alloc_from_hdma.alloc_size_after.size)}")
                type_val = parse_hex_or_int(alloc_from_hdma.alloc_size_after.type)
                print(f"     Type: {decode_type(type_val)}")
                attr_val = parse_hex_or_int(alloc_from_hdma.alloc_size_after.attr)
                attr_decoded = decode_attr(attr_val)
                print(f"     Location: {attr_decoded.get('location', 'UNKNOWN')}")
            else:
                print(f"  ⚠️  No allocation found for hDma={call.hDma}")
            
            print(f"  Offset: {call.offset}")
            print(f"  Length: {format_size(call.length)}")
            print(f"  Status: {call.status}")
            print(f"  Duration: {call.duration_ns} ns ({call.duration_ns/1000:.2f} µs)")
            
            # Decode flags
            flags_val = parse_hex_or_int(call.flags)
            flags_decoded = decode_nvos46_flags(flags_val)
            print(f"  Flags: {call.flags}")
            for key, val in flags_decoded.items():
                print(f"         {key}: {val}")
            
            # Decode flags2
            flags2_val = parse_hex_or_int(call.flags2)
            flags2_decoded = decode_nvos46_flags2(flags2_val)
            print(f"  Flags2: {call.flags2}")
            for key, val in flags2_decoded.items():
                print(f"          {key}: {val}")
            
            print(f"  Kind Override: {call.kindOverride}")
            print(f"  DMA Offset (before): {call.dmaOffset_before}")
            print(f"  DMA Offset (after):  {call.dmaOffset_after}")
            
        elif call_type == 'dupobject':
            print(f"\n{'='*80}")
            print(f"║ 🔄 DUPOBJECT Call #{i} (Line {line_num})")
            print(f"{'='*80}")
            
            print(f"  hClient: {call.hClient}")
            print(f"  hParent: {call.hParent}")
            print(f"  hClientSrc: {call.hClientSrc}")
            print(f"  hObjectSrc: {call.hObjectSrc}")
            print(f"  hObjectDest: {call.hObjectDest}")
            print(f"  Flags: {call.flags}")
            print(f"  Status: {call.status}")
            print(f"  Duration: {call.duration_ns} ns ({call.duration_ns/1000:.2f} µs)")
            
            # Show source allocation if it exists
            source_alloc = alloc_map.get(call.hObjectSrc)
            if source_alloc:
                print(f"  → Source allocation (hObjectSrc={call.hObjectSrc}):")
                print(f"     Line: {source_alloc.line_number}")
                print(f"     Allocated size: {format_size(source_alloc.alloc_size_after.size)}")
                type_val = parse_hex_or_int(source_alloc.alloc_size_after.type)
                print(f"     Type: {decode_type(type_val)}")
                attr_val = parse_hex_or_int(source_alloc.alloc_size_after.attr)
                attr_decoded = decode_attr(attr_val)
                print(f"     Location: {attr_decoded.get('location', 'UNKNOWN')}")
            else:
                print(f"  ⚠️  No allocation found for hObjectSrc={call.hObjectSrc}")
            
            print(f"  ➜ Creates alias: {call.hObjectDest} → {call.hObjectSrc}")


def export_to_json(calls: List[VidHeapControlCall], filename: str):
    """Export vidHeapControl calls to JSON file"""
    data = [asdict(call) for call in calls]
    with open(filename, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"\nExported {len(calls)} vidHeapControl calls to {filename}")


def export_mapmemory_to_json(calls: List[MapMemoryDmaCall], filename: str, alloc_map: Dict[str, VidHeapControlCall] = None):
    """Export mapMemoryDma calls to JSON file with allocation relationships"""
    if alloc_map is None:
        alloc_map = {}
    
    data = []
    for call in calls:
        call_dict = asdict(call)
        
        # Add related allocation info from both hMemory and hDma
        alloc_from_hmemory, alloc_from_hdma = find_related_allocations(call, alloc_map)
        
        if alloc_from_hmemory:
            call_dict['related_allocation_hmemory'] = {
                'source': 'hMemory',
                'line': alloc_from_hmemory.line_number,
                'size': alloc_from_hmemory.alloc_size_after.size,
                'type': alloc_from_hmemory.alloc_size_after.type,
                'hMemory': alloc_from_hmemory.alloc_size_after.hMemory,
                'attr': alloc_from_hmemory.alloc_size_after.attr,
                'attr2': alloc_from_hmemory.alloc_size_after.attr2,
            }
        else:
            call_dict['related_allocation_hmemory'] = None
        
        if alloc_from_hdma:
            call_dict['related_allocation_hdma'] = {
                'source': 'hDma',
                'line': alloc_from_hdma.line_number,
                'size': alloc_from_hdma.alloc_size_after.size,
                'type': alloc_from_hdma.alloc_size_after.type,
                'hMemory': alloc_from_hdma.alloc_size_after.hMemory,
                'attr': alloc_from_hdma.alloc_size_after.attr,
                'attr2': alloc_from_hdma.alloc_size_after.attr2,
            }
        else:
            call_dict['related_allocation_hdma'] = None
        
        data.append(call_dict)
    
    with open(filename, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"\nExported {len(calls)} mapMemoryDma calls to {filename}")


def export_combined_json(vidheap_calls: List[VidHeapControlCall], mapmemory_calls: List[MapMemoryDmaCall], 
                         filename: str, alloc_map: Dict[str, VidHeapControlCall] = None, source_file: str = None):
    """Export both vidHeapControl and mapMemoryDma calls to a single combined JSON file"""
    if alloc_map is None:
        alloc_map = {}
    
    # Prepare vidHeapControl data
    vidheap_data = [asdict(call) for call in vidheap_calls]
    for item in vidheap_data:
        item['call_type'] = 'vidHeapControl'
    
    # Prepare mapMemoryDma data with relationships
    mapmemory_data = []
    for call in mapmemory_calls:
        call_dict = asdict(call)
        call_dict['call_type'] = 'mapMemoryDma'
        
        # Add related allocation info
        alloc_from_hmemory, alloc_from_hdma, _, _ = find_related_allocations(call, alloc_map)
        
        if alloc_from_hmemory:
            call_dict['related_allocation_hmemory'] = {
                'source': 'hMemory',
                'line': alloc_from_hmemory.line_number,
                'size': alloc_from_hmemory.alloc_size_after.size,
                'type': alloc_from_hmemory.alloc_size_after.type,
                'hMemory': alloc_from_hmemory.alloc_size_after.hMemory,
                'attr': alloc_from_hmemory.alloc_size_after.attr,
                'attr2': alloc_from_hmemory.alloc_size_after.attr2,
            }
        else:
            call_dict['related_allocation_hmemory'] = None
        
        if alloc_from_hdma:
            call_dict['related_allocation_hdma'] = {
                'source': 'hDma',
                'line': alloc_from_hdma.line_number,
                'size': alloc_from_hdma.alloc_size_after.size,
                'type': alloc_from_hdma.alloc_size_after.type,
                'hMemory': alloc_from_hdma.alloc_size_after.hMemory,
                'attr': alloc_from_hdma.alloc_size_after.attr,
                'attr2': alloc_from_hdma.alloc_size_after.attr2,
            }
        else:
            call_dict['related_allocation_hdma'] = None
        
        mapmemory_data.append(call_dict)
    
    # Combine both lists and sort by line number
    combined_data = vidheap_data + mapmemory_data
    combined_data.sort(key=lambda x: x['line_number'])
    
    # Create final structure
    output = {
        'metadata': {
            'source_file': source_file,
            'total_calls': len(combined_data),
            'vidheap_calls': len(vidheap_calls),
            'mapmemory_calls': len(mapmemory_calls),
            'allocation_map_entries': len(alloc_map),
        },
        'calls': combined_data
    }
    
    with open(filename, 'w') as f:
        json.dump(output, f, indent=2)
    print(f"\nExported combined {len(vidheap_calls)} vidHeapControl + {len(mapmemory_calls)} mapMemoryDma calls to {filename}")


def main():
    """Main function"""
    import argparse
    
    parser = argparse.ArgumentParser(
        description='Process vidHeapControl and mapMemoryDma calls from rmlog file',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('rmlog_file', nargs='?', default='rmlog',
                        help='Path to rmlog file (default: rmlog)')
    parser.add_argument('--json', metavar='FILE',
                        help='Export both call types to a combined JSON file (sorted by line number)')
    parser.add_argument('--detailed', type=int, metavar='N', default=10,
                        help='Show detailed info for first N calls (default: 10)')
    parser.add_argument('--no-summary', action='store_true',
                        help='Skip summary output')
    parser.add_argument('--no-detailed', action='store_true',
                        help='Skip detailed call output')
    parser.add_argument('--only-vidheap', action='store_true',
                        help='Only process vidHeapControl calls')
    parser.add_argument('--only-mapmemory', action='store_true',
                        help='Only process mapMemoryDma calls')
    parser.add_argument('--filter-type', nargs='+', 
                        choices=['vidheap', 'mapmemory', 'dupobject'],
                        help='Filter to show only specific call types (can specify multiple)')
    
    args = parser.parse_args()
    
    print(f"Processing {args.rmlog_file}...")
    vidheap_calls, mapmemory_calls, dupobject_calls = process_rmlog(args.rmlog_file)
    
    # Build alias map from dupObject calls
    alias_map = build_alias_map(dupobject_calls)
    print(f"Found {len(dupobject_calls)} dupObject calls ({len(alias_map)} successful aliases)")
    
    # Build allocation map for connecting calls (including aliases)
    alloc_map = build_allocation_map(vidheap_calls, alias_map)
    print(f"Built allocation map with {len(alloc_map)} entries")
    
    # Determine what to show
    if args.filter_type:
        # Use --filter-type if specified
        show_vidheap = 'vidheap' in args.filter_type
        show_mapmemory = 'mapmemory' in args.filter_type
        show_dupobject = 'dupobject' in args.filter_type
    else:
        # Fall back to --only-* flags
        show_vidheap = not args.only_mapmemory
        show_mapmemory = not args.only_vidheap
        show_dupobject = True  # Show dupobject by default unless filtered
    
    # Print summaries
    if show_vidheap:
        if not vidheap_calls:
            print("No vidHeapControl calls found!")
        else:
            print(f"Found {len(vidheap_calls)} vidHeapControl calls")
            if not args.no_summary:
                print_summary(vidheap_calls)
    
    if show_mapmemory:
        if not mapmemory_calls:
            print("No mapMemoryDma calls found!")
        else:
            print(f"Found {len(mapmemory_calls)} mapMemoryDma calls")
            
            # Calculate how many mappings have related allocations
            mappings_with_hmemory = sum(1 for call in mapmemory_calls if call.hMemory in alloc_map)
            mappings_with_hdma = sum(1 for call in mapmemory_calls if call.hDma in alloc_map)
            mappings_with_any = sum(1 for call in mapmemory_calls if call.hMemory in alloc_map or call.hDma in alloc_map)
            print(f"  → {mappings_with_hmemory} mappings have hMemory allocations ({mappings_with_hmemory*100//len(mapmemory_calls)}%)")
            print(f"  → {mappings_with_hdma} mappings have hDma allocations ({mappings_with_hdma*100//len(mapmemory_calls)}%)")
            print(f"  → {mappings_with_any} mappings have at least one allocation ({mappings_with_any*100//len(mapmemory_calls)}%)")
            
            if not args.no_summary:
                print_mapmemory_summary(mapmemory_calls)
    
    # Print detailed calls (interleaved)
    if not args.no_detailed:
        # Filter calls based on what should be shown
        vidheap_to_show = vidheap_calls if show_vidheap else []
        mapmemory_to_show = mapmemory_calls if show_mapmemory else []
        dupobject_to_show = dupobject_calls if show_dupobject else []
        print_interleaved_detailed(vidheap_to_show, mapmemory_to_show, dupobject_to_show, args.detailed, alloc_map, alias_map, args.rmlog_file)
    
    # Export combined JSON if requested
    if args.json:
        export_combined_json(vidheap_calls, mapmemory_calls, args.json, alloc_map, args.rmlog_file)
    
    return 0


if __name__ == '__main__':
    sys.exit(main())

