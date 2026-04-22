#!/bin/sh

# Generate HTML report from k6 metrics.json
# Usage: ./generate-report.sh /reports/metrics.json /reports/report.html <k6_exit_code>

METRICS_FILE="$1"
OUTPUT_FILE="$2"
K6_EXIT_CODE="${3:-0}"

if [ ! -f "$METRICS_FILE" ]; then
    echo "Metrics file not found: $METRICS_FILE"
    exit 1
fi

# Single awk pass: extract values to per-page temp files, track failures
rm -f /tmp/k6_page_*.txt
awk '
    /"type":"Point"/ {
        metric = ""
        if (match($0, /"metric":"[^"]+"/)) {
            metric = substr($0, RSTART, RLENGTH)
            gsub(/"metric":"|"/, "", metric)
        }

        val = ""
        if (match($0, /"value":[0-9.]+/)) {
            val = substr($0, RSTART, RLENGTH)
            sub(/"value":/, "", val)
        }

        if (val == "" || metric == "") next

        if (metric ~ /^duration_/) {
            print val >> "/tmp/k6_page_" metric ".txt"
            dur_sum[metric] += val
            dur_count[metric]++
            if (!(metric in dur_min) || val+0 < dur_min[metric]) dur_min[metric] = val+0
            if (!(metric in dur_max) || val+0 > dur_max[metric]) dur_max[metric] = val+0
        }

        if (metric == "http_req_failed" && val == 1) {
            grp = "unknown"
            if (match($0, /"group":"[^"]*::([^"]+)"/)) {
                grp = substr($0, RSTART, RLENGTH)
                sub(/.*::/, "", grp)
                sub(/"$/, "", grp)
            }
            fail_count[grp]++
        }
    }
    END {
        for (metric in dur_count) {
            printf "%s,%d,%.2f,%.2f,%.2f\n",
                metric, dur_count[metric], dur_sum[metric]/dur_count[metric], dur_min[metric], dur_max[metric] \
                >> "/tmp/k6_page_meta.txt"
        }
        for (grp in fail_count) {
            print grp "," fail_count[grp] >> "/tmp/failure_stats.csv"
        }
    }
' "$METRICS_FILE"

# Calculate p95 per page metric, write duration_stats.csv
JOURNEY_ORDER=$([ -f /tmp/k6_page_meta.txt ] && awk -F',' '{print $1}' /tmp/k6_page_meta.txt || true)

> /tmp/duration_stats.csv
for metric in $JOURNEY_ORDER; do
    [ -f "/tmp/k6_page_meta.txt" ] || continue
    line=$(grep "^${metric}," /tmp/k6_page_meta.txt)
    [ -z "$line" ] && continue
    cnt=$(echo "$line" | cut -d',' -f2)
    avg=$(echo "$line" | cut -d',' -f3)
    mn=$(echo "$line" | cut -d',' -f4)
    mx=$(echo "$line" | cut -d',' -f5)
    val_file="/tmp/k6_page_${metric}.txt"
    sort -n "$val_file" > /tmp/k6_sorted.txt
    p95_idx=$(awk "BEGIN {n=$cnt; idx=int((n*95+99)/100); if(idx<1)idx=1; if(idx>n)idx=n; print idx}")
    p95=$(sed -n "${p95_idx}p" /tmp/k6_sorted.txt | awk '{printf "%.2f", $1}')
    # Derive page name from metric name: strip duration_ prefix, replace _ with -
    page=$(echo "$metric" | sed 's/^duration_//; s/_/-/g')
    echo "${page},${cnt},${avg},${mn},${mx},${p95}" >> /tmp/duration_stats.csv
done
sort -t',' -k6 -rn /tmp/duration_stats.csv -o /tmp/duration_stats.csv
rm -f /tmp/k6_page_*.txt /tmp/k6_page_meta.txt /tmp/k6_sorted.txt

# Generate HTML
cat > "$OUTPUT_FILE" << 'HTMLHEADER'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>k6 Performance Test Report</title>
    <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            margin: 0;
            padding: 20px;
            background: #f5f5f5;
            color: #333;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .summary-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .summary-card h3 { margin: 0 0 10px 0; color: #7f8c8d; font-size: 14px; }
        .summary-card .value { font-size: 32px; font-weight: bold; color: #2c3e50; }
        table {
            width: 100%;
            border-collapse: collapse;
            background: white;
            border-radius: 8px;
            overflow: hidden;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        th, td {
            padding: 12px 15px;
            text-align: left;
            border-bottom: 1px solid #ecf0f1;
        }
        th {
            background: #3498db;
            color: white;
            font-weight: 600;
        }
        tr:hover { background: #f8f9fa; }
        tr:last-child td { border-bottom: none; }
        .pass { color: #27ae60; font-weight: bold; }
        .fail { color: #e74c3c; font-weight: bold; }
        .value.pass { color: #27ae60; }
        .value.fail { color: #e74c3c; }
        .duration { font-family: monospace; text-align: right; }
        .numeric { text-align: right; }
        .timestamp { color: #95a5a6; font-size: 14px; margin-bottom: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>k6 Performance Test Report</h1>
HTMLHEADER

# Add timestamp
echo "        <p class=\"timestamp\">Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC') &nbsp;&bull;&nbsp; <a href=\"metrics.json\">Download raw metrics</a></p>" >> "$OUTPUT_FILE"

# Calculate totals for summary
TOTAL_REQUESTS=$(awk -F',' '{sum+=$2} END {print sum+0}' /tmp/duration_stats.csv)
OVERALL_AVG=$(awk -F',' '{sum+=$3; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' /tmp/duration_stats.csv)

# Slowest page p95: max p95 across all duration_* metrics
JOURNEY_P95=$(awk -F',' 'BEGIN{max=0} {if($6+0>max) max=$6+0} END{if(max>0) printf "%.2f", max; else print "N/A"}' /tmp/duration_stats.csv)
[ -z "$JOURNEY_P95" ] && JOURNEY_P95="N/A"

# Count total failures
TOTAL_FAILURES=0
if [ -f /tmp/failure_stats.csv ] && [ -s /tmp/failure_stats.csv ]; then
    while IFS=',' read -r group failures; do
        TOTAL_FAILURES=$((TOTAL_FAILURES + failures))
    done < /tmp/failure_stats.csv
fi

if [ "$K6_EXIT_CODE" -eq 0 ]; then
    STATUS_CLASS="pass"
    STATUS_TEXT="PASSED"
else
    STATUS_CLASS="fail"
    STATUS_TEXT="FAILED"
fi

# Add summary cards
cat >> "$OUTPUT_FILE" << SUMMARY
        <div class="summary">
            <div class="summary-card">
                <h3>Status</h3>
                <div class="value ${STATUS_CLASS}">${STATUS_TEXT}</div>
            </div>
            <div class="summary-card">
                <h3>Total Requests</h3>
                <div class="value">${TOTAL_REQUESTS}</div>
            </div>
            <div class="summary-card">
                <h3>Failed Requests</h3>
                <div class="value">${TOTAL_FAILURES}</div>
            </div>
            <div class="summary-card">
                <h3>Slowest Journey p95</h3>
                <div class="value">${JOURNEY_P95}ms</div>
            </div>
        </div>

        <h2>Page Load Times</h2>
        <table>
            <thead>
                <tr>
                    <th>Page</th>
                    <th style="text-align:right">Requests</th>
                    <th style="text-align:right">Avg (ms)</th>
                    <th style="text-align:right">Min (ms)</th>
                    <th style="text-align:right">Max (ms)</th>
                    <th style="text-align:right">P95 (ms) &#9660;</th>
                </tr>
            </thead>
            <tbody>
SUMMARY

# Add table rows
while IFS=',' read -r page requests avg min max p95; do
    cat >> "$OUTPUT_FILE" << ROW
                <tr>
                    <td><strong>${page}</strong></td>
                    <td class="numeric">${requests}</td>
                    <td class="duration">${avg}</td>
                    <td class="duration">${min}</td>
                    <td class="duration">${max}</td>
                    <td class="duration">${p95}</td>
                </tr>
ROW
done < /tmp/duration_stats.csv

# Close response times table
cat >> "$OUTPUT_FILE" << 'TABLECLOSE'
            </tbody>
        </table>
TABLECLOSE

# Extract error details (failed requests with their URLs and status codes)
> /tmp/error_details.csv
grep '"metric":"http_req_failed"' "$METRICS_FILE" | grep '"type":"Point"' | grep '"value":1' > /tmp/failed_requests.txt || true

if [ -s /tmp/failed_requests.txt ]; then
    while read -r line; do
        # Extract group
        err_group=$(echo "$line" | sed -n 's/.*"group":"::woodland-grant::\([^"]*\)".*/\1/p')
        if [ -z "$err_group" ]; then
            err_group=$(echo "$line" | sed -n 's/.*"group":"::\([^"]*\)".*/\1/p')
        fi
        if [ -z "$err_group" ]; then
            err_group="unknown"
        fi

        # Extract URL
        err_url=$(echo "$line" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
        err_url=${err_url:-"N/A"}

        # Extract status code
        err_status=$(echo "$line" | sed -n 's/.*"status":"\{0,1\}\([0-9]*\)"\{0,1\}.*/\1/p')
        err_status=${err_status:-"N/A"}

        # Extract method
        err_method=$(echo "$line" | sed -n 's/.*"method":"\([^"]*\)".*/\1/p')
        err_method=${err_method:-"N/A"}

        echo "${err_group},${err_method},${err_status},${err_url}" >> /tmp/error_details.csv
    done < /tmp/failed_requests.txt

    # Add errors table
    cat >> "$OUTPUT_FILE" << 'ERRORHEADER'

        <h2>Errors</h2>
        <table>
            <thead>
                <tr>
                    <th>Group</th>
                    <th>Method</th>
                    <th>Status</th>
                    <th>URL</th>
                </tr>
            </thead>
            <tbody>
ERRORHEADER

    while IFS=',' read -r err_group err_method err_status err_url; do
        cat >> "$OUTPUT_FILE" << ERRORROW
                <tr>
                    <td><strong>${err_group}</strong></td>
                    <td>${err_method}</td>
                    <td class="fail">${err_status}</td>
                    <td style="word-break: break-all;">${err_url}</td>
                </tr>
ERRORROW
    done < /tmp/error_details.csv

    cat >> "$OUTPUT_FILE" << 'ERRORFOOTER'
            </tbody>
        </table>
ERRORFOOTER
fi

rm -f /tmp/failed_requests.txt /tmp/error_details.csv

# Extract failed checks
> /tmp/failed_checks.csv
grep '"metric":"checks"' "$METRICS_FILE" | grep '"type":"Point"' | grep '"value":0' | while read -r line; do
    chk=$(echo "$line" | sed -n 's/.*"check":"\([^"]*\)".*/\1/p')
    grp=$(echo "$line" | sed -n 's/.*"group":"::\([^"]*\)".*/\1/p')
    echo "${grp:-unknown},${chk:-unknown}" >> /tmp/failed_checks.csv
done

if [ -s /tmp/failed_checks.csv ]; then
    cat >> "$OUTPUT_FILE" << 'CHECKHEADER'

        <h2>Failed Checks</h2>
        <table>
            <thead>
                <tr>
                    <th>Group</th>
                    <th>Check</th>
                </tr>
            </thead>
            <tbody>
CHECKHEADER

    while IFS=',' read -r chk_group chk_name; do
        cat >> "$OUTPUT_FILE" << CHECKROW
                <tr>
                    <td><strong>${chk_group}</strong></td>
                    <td class="fail">${chk_name}</td>
                </tr>
CHECKROW
    done < /tmp/failed_checks.csv

    cat >> "$OUTPUT_FILE" << 'CHECKFOOTER'
            </tbody>
        </table>
CHECKFOOTER
fi

rm -f /tmp/failed_checks.csv

# Close HTML
cat >> "$OUTPUT_FILE" << 'HTMLFOOTER'
    </div>
</body>
</html>
HTMLFOOTER

rm -rf /tmp/k6_groups /tmp/duration_stats.csv /tmp/failure_stats.csv /tmp/sorted_values.txt

echo "Report generated: $OUTPUT_FILE"
