# AWS Inspector Enhanced Findings → CSV
# Optional filters via --arg:
#   cutoff  YYYY-MM-DD  exclude findings with vendorCreatedAt after this date (default: no filter)
#   paths   regex       include only packages where filePath matches regex (default: all packages)
#
# Usage:
#   jq -rf inspector-report.jq input.json
#   jq -rf inspector-report.jq --arg cutoff "2026-03-30" input.json
#   jq -rf inspector-report.jq --arg paths "filebeat|metricbeat" input.json
#   jq -rf inspector-report.jq --arg cutoff "2026-03-30" --arg paths "filebeat|metricbeat" input.json

def csv_escape:
  if . == null then ""
  elif type == "number" then tostring
  else tostring | gsub("\""; "\"\"") | "\"" + . + "\""
  end;

def row(fields): fields | map(csv_escape) | join(",");

.imageScanFindings.enhancedFindings[] |
  select(
    ($cutoff // "") == "" or
    .packageVulnerabilityDetails.vendorCreatedAt == null or
    (.packageVulnerabilityDetails.vendorCreatedAt | split("T")[0]) <= $cutoff
  ) |
  . as $f |
  ($f.packageVulnerabilityDetails.cvss |
    map(select(.source == "NVD")) | first //
    $f.packageVulnerabilityDetails.cvss[0] //
    {baseScore: null, scoringVector: null}
  ) as $cvss |
  ($f.packageVulnerabilityDetails.vulnerablePackages // [{}] |
    if ($paths // "") != "" then
      map(select(.filePath != null and (.filePath | test($paths; "i"))))
    else
      .
    end
  ) |
  select(length > 0) |
  .[] |
  row([
    $f.packageVulnerabilityDetails.vulnerabilityId,
    $f.severity,
    $cvss.baseScore,
    $cvss.scoringVector,
    .version,
    .fixedInVersion,
    .filePath,
    .name,
    $f.description
  ])
