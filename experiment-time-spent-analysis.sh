#!/bin/bash

set -e

TEMP_DATA="/tmp/field_filtering_data.dat"
echo "# pageSize overhead_50th overhead_95th" > "$TEMP_DATA"

for dir in present-fields-all/orgunits-page-*/; do
    [ ! -d "$dir" ] && continue

    # Skip if no simulation.csv files found
    if ! ls "$dir"/*/simulation.csv >/dev/null 2>&1; then
        continue
    fi

    page_size=$(basename "$dir" | sed 's/orgunits-page-//')
    echo "Processing page size: $page_size"

    gstat "$dir" > "${dir}percentiles.csv"
    percentiles_data=$(tail -n +2 "${dir}percentiles.csv")

    with_filtering=$(echo "$percentiles_data" | head -n 1)
    without_filtering=$(echo "$percentiles_data" | tail -n 1)

    [ -z "$with_filtering" ] || [ -z "$without_filtering" ] && continue

    with_50th=$(echo "$with_filtering" | awk -F',' '{print $(NF-5)}')
    with_95th=$(echo "$with_filtering" | awk -F',' '{print $(NF-3)}')
    without_50th=$(echo "$without_filtering" | awk -F',' '{print $(NF-5)}')
    without_95th=$(echo "$without_filtering" | awk -F',' '{print $(NF-3)}')

    overhead_50th=$(echo "$with_50th - $without_50th" | bc)
    overhead_95th=$(echo "$with_95th - $without_95th" | bc)

    echo "$page_size $overhead_50th $overhead_95th" >> "$TEMP_DATA"
done

# Sort data by page size
sort -n "$TEMP_DATA" > "${TEMP_DATA}.sorted"

cat > /tmp/plot.gp << 'EOF'
set terminal pngcairo size 1000,600
set output 'field-filtering-overhead.png'
set title "Field Filtering Overhead vs Page Size"
set xlabel "Page Size"
set ylabel "Overhead (ms)"
set key top left
plot '/tmp/field_filtering_data.dat.sorted' using 1:2 with linespoints title "50th percentile" lw 2, \
     '/tmp/field_filtering_data.dat.sorted' using 1:3 with linespoints title "95th percentile" lw 2
EOF

gnuplot /tmp/plot.gp
echo "Plot saved as field-filtering-overhead.png"
rm -f "$TEMP_DATA" "${TEMP_DATA}.sorted" /tmp/plot.gp
