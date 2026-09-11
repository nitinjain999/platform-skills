# Task: Identify distinct relevant findings from scanner results

The file `trivy-results.json` contains vulnerability scan results for a container image.

Deduplicate and prioritize the findings:

1. How many **distinct** vulnerabilities are present? (CVE-2024-1234 appears twice because OpenSSL ships libssl3 and libcrypto3 as separate packages, but it's one vulnerability.)

2. Which findings are **critical or high severity** and have a fix available?

3. Which findings have **no fix available** and must be mitigated or accepted as residual risk?

4. What is the recommended remediation priority?

Do NOT omit any critical or high-severity finding. Report complete, partial, or blocked.
