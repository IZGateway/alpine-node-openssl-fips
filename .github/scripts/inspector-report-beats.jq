# AWS Inspector Enhanced Findings → CSV (beats filter)
# Includes only findings where at least one vulnerable package has a filePath
# containing "filebeat" or "metricbeat". Rows are emitted per vulnerable package,
# but only for the beats-related packages within each finding.
# Usage: jq -rf inspector-report-beats.jq <findings.json>

def csv_escape:
  if . == null then ""
  elif type == "number" then tostring
  else tostring | gsub("\""; "\"\"") | "\"" + . + "\""
  end;

def row(fields): fields | map(csv_escape) | join(",");

.imageScanFindings.enhancedFindings[] |
  . as $f |
  ($f.packageVulnerabilityDetails.vulnerablePackages // [{}] |
    map(select(.filePath != null and (.filePath | test("filebeat|metricbeat"; "i"))))
  ) |
  select(length > 0) |
  . as $pkgs |
  ($f.packageVulnerabilityDetails.cvss | map(select(.source == "NVD")) | first // $f.packageVulnerabilityDetails.cvss[0] // {baseScore: null, scoringVector: null}) as $cvss |
  $pkgs[] |
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
