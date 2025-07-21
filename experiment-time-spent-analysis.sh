#!/bin/bash

set -e

TEMP_DATA="/tmp/field_filtering_data.dat"
echo "# pageSize overhead_50th overhead_95th" > "$TEMP_DATA"

for dir in present-fields-all/orgunits-page-*/; do
    [ ! -d "$dir" ] && continue

    # Skip if no simulation.csv files found
    if ! ls "$dir"/*/simulation.csv >/dev/null 2>&1; then
        echo "Warning: No simulation.csv found in $dir"
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

# Extract request name from first simulation.csv file for title
first_sim_csv=$(find present-fields-all/orgunits-page-*/*/simulation.csv | head -n 1)
# Find the first request line and extract everything between quotes, escape & for gnuplot
request_name=$(grep "^request," "$first_sim_csv" | head -n 1 | sed 's/.*"\([^"]*\)".*/\1/' | sed 's/&/\\\\&/g')

cat > /tmp/plot.gp << EOF
set terminal pngcairo size 1000,600
set output 'field-filtering-overhead.png'
set title "Difference in response times for requests against instance with and without field filtering\\n$request_name"
set xlabel "pageSize"
set ylabel "Field filtering cost (ms)"
set key top left
plot '/tmp/field_filtering_data.dat' using 1:2 with linespoints title "50th percentile" lw 2, \
     '/tmp/field_filtering_data.dat' using 1:3 with linespoints title "95th percentile" lw 2
EOF

gnuplot /tmp/plot.gp
echo "Plot saved as field-filtering-overhead.png"
rm -f "$TEMP_DATA" /tmp/plot.gp
