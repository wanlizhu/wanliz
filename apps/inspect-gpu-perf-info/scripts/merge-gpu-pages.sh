#!/usr/bin/env bash

main() {
    awk '
    function hex_to_dec(x) { return strtonum(x) }
    match($0,/^[[:space:]]*(0x[0-9A-Fa-f]+)[[:space:]]*-[[:space:]]*(0x[0-9A-Fa-f]+)([[:space:]]*=>[[:space:]]*0x[0-9A-Fa-f]+[[:space:]]*-[[:space:]]*0x[0-9A-Fa-f]+)?[[:space:]]*(.*)$/,m){
        attr_text = m[4]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", attr_text)
        printf "%s\t%d\t%d\t%s\t%s\n",
               attr_text, hex_to_dec(m[1]), hex_to_dec(m[2]), m[1], m[2]
    }
    ' | sort -t $'\t' -k1,1 -k2,2n | awk '
    BEGIN { FS = OFS = "\t" }
    function human_size(bytes,   v, unit) {
        if (bytes >= 1024*1024*1024) {
            v = bytes / (1024*1024*1024)
            unit = "GB"
        } else if (bytes >= 1024*1024) {
            v = bytes / (1024*1024)
            unit = "MB"
        } else if (bytes >= 1024) {
            v = bytes / 1024
            unit = "KB"
        } else {
            v = bytes
            unit = "B"
        }
        return sprintf("%.2f %s", v, unit)
    }

    {
        attr         = $1
        va_start_dec = $2 + 0
        va_end_dec   = $3 + 0
        va_start_hex = $4
        va_end_hex   = $5

        if (!have_range) {
            have_range         = 1
            prev_attr          = attr
            prev_va_start_hex  = va_start_hex
            prev_va_end_hex    = va_end_hex
            prev_va_start_dec  = va_start_dec
            prev_va_end_dec    = va_end_dec
            next
        }

        if (attr == prev_attr && va_start_dec <= prev_va_end_dec + 1) {
            if (va_end_dec > prev_va_end_dec) {
                prev_va_end_dec = va_end_dec
                prev_va_end_hex = va_end_hex
            }
        } else {
            bytes = prev_va_end_dec - prev_va_start_dec + 1
            size_str = human_size(bytes)
            if (prev_attr != "")
                printf "%s - %s %s %s\n", prev_va_start_hex, prev_va_end_hex, prev_attr, size_str
            else
                printf "%s - %s %s\n", prev_va_start_hex, prev_va_end_hex, size_str

            prev_attr          = attr
            prev_va_start_hex  = va_start_hex
            prev_va_end_hex    = va_end_hex
            prev_va_start_dec  = va_start_dec
            prev_va_end_dec    = va_end_dec
        }
    }

    END {
        if (have_range) {
            bytes = prev_va_end_dec - prev_va_start_dec + 1
            size_str = human_size(bytes)
            if (prev_attr != "")
                printf "%s - %s %s %s\n", prev_va_start_hex, prev_va_end_hex, prev_attr, size_str
            else
                printf "%s - %s %s\n", prev_va_start_hex, prev_va_end_hex, size_str
        }
    }'
}

[[ "$#" -gt 0 ]] && exec < "$1"
main
