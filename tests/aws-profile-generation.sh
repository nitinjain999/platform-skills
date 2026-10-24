#!/usr/bin/env bash
# Validate the documented generated profiles using synthetic configuration only.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 - <<'PY'
import configparser
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

text = Path("skills/aws-profile/SKILL.md").read_text()
section = text.split("**With `--generate-profiles`**", 1)[1].split("**Steps:**", 1)[0]
examples = re.findall(r"```ini\n(.*?)```", section, re.S)
assert len(examples) == 2, "Expected session-based and legacy generated profile examples"
aws = shutil.which("aws")

with tempfile.TemporaryDirectory(prefix="aws-profile-generation-") as tmp:
    for kind, example in zip(("session", "legacy"), examples):
        config = configparser.ConfigParser()
        config.read_string(example)
        profiles = [name for name in config.sections() if name.startswith("profile ")]
        assert profiles, f"{kind}: no generated profiles"
        if kind == "session":
            # Existing organization session, separate from generated profiles.
            config.read_string(
                "[sso-session platform]\n"
                "sso_start_url = https://myorg.awsapps.com/start\n"
                "sso_region = eu-west-1\n"
            )
        for profile in profiles:
            values = config[profile]
            assert values.get("sso_account_id") and values.get("sso_role_name")
            assert values.get("region")
            if kind == "session":
                assert values.get("sso_session") == "platform"
                session = config[f"sso-session {values['sso_session']}"]
                assert session.get("sso_start_url") and session.get("sso_region")
                fields = ("sso_session", "sso_account_id", "sso_role_name", "region")
            else:
                assert not values.get("sso_session")
                assert values.get("sso_start_url") and values.get("sso_region")
                fields = ("sso_start_url", "sso_region", "sso_account_id", "sso_role_name", "region")
            if aws:
                path = Path(tmp, f"{kind}.ini")
                with path.open("w") as stream:
                    config.write(stream)
                env = {
                    "PATH": os.environ["PATH"], "AWS_CONFIG_FILE": str(path),
                    "AWS_SHARED_CREDENTIALS_FILE": os.devnull,
                    "AWS_EC2_METADATA_DISABLED": "true", "AWS_PAGER": "",
                }
                for key in fields:
                    result = subprocess.run(
                        [aws, "configure", "get", key, "--profile", profile.removeprefix("profile ")],
                        env=env, text=True, capture_output=True, check=True,
                    )
                    assert result.stdout.strip() == values[key], (profile, key, result.stderr)
        print(f"PASS: {kind} generated profiles have complete SSO configuration")
if aws:
    print("PASS: AWS CLI resolves the documented profile metadata offline")
else:
    print("INFO: AWS CLI unavailable; validated synthetic INI configuration only")
PY
